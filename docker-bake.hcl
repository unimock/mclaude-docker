# Image build definition.
#   Local (host arch):  VERSION=$(cat VERSION) docker buildx bake --load
#   Multi-arch + push:  ./push.sh   (target "release")

# unimock/mclaude tag to build on (the VERSION file); also our own tag.
variable "VERSION" {
  default = "latest"
}

# org.opencontainers.image.created label.
variable "BUILD_DATE" {
  default = "unknown"
}

group "default" {
  targets = ["mclaude-docker"]
}

target "mclaude-docker" {
  context = "."
  tags = [
    "unimock/mclaude-docker:latest",
    "unimock/mclaude-docker:${VERSION}",
  ]
  args = {
    MCLAUDE_VERSION = VERSION
    BUILD_DATE      = BUILD_DATE
  }
}

target "release" {
  inherits  = ["mclaude-docker"]
  platforms = ["linux/amd64", "linux/arm64"]
}
