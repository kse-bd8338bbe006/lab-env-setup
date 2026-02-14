# Choose your platform module:
# For macOS/Linux: use "./macos"
# For Windows: use "./windows"

# Example for macOS:
# module "multipass" {
#   source = "./macos"
# }

# Example for Windows:
# module "multipass" {
#   source = "./windows"
# }

# Default (backward compatibility - macOS/Linux)
module "multipass" {
  source = "./macos"
}
