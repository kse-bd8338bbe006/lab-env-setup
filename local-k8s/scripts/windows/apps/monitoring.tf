# Kube-Prometheus-Stack Installation
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  version          = "80.14.0"
  create_namespace = true

  values = [
    yamlencode({
      # Prometheus configuration
      prometheus = {
        prometheusSpec = {
          retention = "15d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
          resources = {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }

      # Grafana configuration
      grafana = {
        enabled       = true
        adminPassword = "admin"

        service = {
          type = "ClusterIP"
        }

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }

        persistence = {
          enabled = true
          size    = "5Gi"
        }
      }

      # AlertManager configuration
      alertmanager = {
        enabled = true

        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "5Gi"
                  }
                }
              }
            }
          }
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }

      # Node Exporter configuration
      nodeExporter = {
        enabled = true
      }

      # Kube State Metrics configuration
      kubeStateMetrics = {
        enabled = true
      }

      # Default rules
      defaultRules = {
        create = true
        rules = {
          alertmanager                = true
          etcd                        = false  # Disabled - etcd not accessible in kubeadm setup
          configReloaders             = true
          general                     = true
          k8s                         = true
          kubeApiserver               = true
          kubeApiserverAvailability   = true
          kubeApiserverSlos           = true
          kubelet                     = true
          kubeProxy                   = false  # Disabled - kube-proxy metrics not exposed by default
          kubePrometheusGeneral       = true
          kubePrometheusNodeRecording = true
          kubernetesApps              = true
          kubernetesResources         = true
          kubernetesStorage           = true
          kubernetesSystem            = true
          kubeScheduler               = false  # Disabled - scheduler metrics not exposed by default
          kubeStateMetrics            = true
          network                     = true
          node                        = true
          nodeExporterAlerting        = true
          nodeExporterRecording       = true
          prometheus                  = true
          prometheusOperator          = true
        }
      }
    })
  ]

  wait    = true
  timeout = 600

  depends_on = [
    helm_release.nfs_provisioner
  ]
}

# Ingress for Grafana
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana-ingress"
    namespace = "monitoring"
    annotations = {
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "false"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "grafana.${local.haproxy_ip}.nip.io"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "kube-prometheus-stack-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# Ingress for Prometheus
resource "kubernetes_ingress_v1" "prometheus" {
  metadata {
    name      = "prometheus-ingress"
    namespace = "monitoring"
    annotations = {
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "false"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "prometheus.${local.haproxy_ip}.nip.io"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "kube-prometheus-stack-prometheus"
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# Ingress for AlertManager
resource "kubernetes_ingress_v1" "alertmanager" {
  metadata {
    name      = "alertmanager-ingress"
    namespace = "monitoring"
    annotations = {
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "false"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "alertmanager.${local.haproxy_ip}.nip.io"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "kube-prometheus-stack-alertmanager"
              port {
                number = 9093
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

output "grafana_url" {
  value       = "http://grafana.${local.haproxy_ip}.nip.io"
  description = "Grafana URL"
}

output "grafana_credentials" {
  value       = "admin / admin"
  description = "Grafana default credentials"
}

output "prometheus_url" {
  value       = "http://prometheus.${local.haproxy_ip}.nip.io"
  description = "Prometheus URL"
}

output "alertmanager_url" {
  value       = "http://alertmanager.${local.haproxy_ip}.nip.io"
  description = "AlertManager URL"
}
