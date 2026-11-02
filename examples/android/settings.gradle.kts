pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
 repositories {
  maven { url=uri("../../dist/maven") }
  google(); mavenCentral()
 }
}
rootProject.name = "cubegin-package-consumer"
