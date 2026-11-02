plugins { id("com.android.library"); id("org.jetbrains.kotlin.android"); id("maven-publish") }
group = "io.github.deweyou"
version = "0.1.0"
android {
    namespace = "io.github.deweyou.cubegin"
    compileSdk = 35
    ndkVersion = "28.2.13676358"
    defaultConfig { minSdk = 23; consumerProguardFiles("consumer-rules.pro") }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    sourceSets.getByName("test").resources.srcDir("../../../fixtures")
    publishing { singleVariant("release") { withSourcesJar() } }
    testOptions.unitTests.all {
        it.jvmArgs("-Djna.library.path=" + rootProject.projectDir.resolve("../../target/release").absolutePath)
    }
}
val verifyNativeArtifacts = tasks.register("verifyNativeArtifacts") {
 doLast {
  for (abi in listOf("arm64-v8a", "armeabi-v7a", "x86_64")) {
   check(file("src/main/jniLibs/$abi/libcubegin_native.so").isFile) {
    "Missing $abi native library; run cargo xtask build-sdk android before packaging"
   }
  }
 }
}
tasks.matching { it.name == "bundleReleaseAar" }.configureEach { dependsOn(verifyNativeArtifacts) }
dependencies {
    api("net.java.dev.jna:jna:5.17.0@aar")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250107")
    // Host unit tests need JNA's desktop dispatcher; the shipped AAR uses Android natives.
    testRuntimeOnly("net.java.dev.jna:jna:5.17.0@jar")
}
afterEvaluate {
 publishing.publications.create<MavenPublication>("release") {
  from(components["release"])
  artifactId = "cubegin"
  pom {
   name.set("Cubegin"); description.set("Rust-powered 3x3 cube SDK")
   url.set("https://github.com/deweyou/cubekit")
   licenses { license { name.set("GPL-3.0-only"); url.set("https://www.gnu.org/licenses/gpl-3.0.html") } }
   developers { developer { id.set("deweyou"); name.set("Dewey") } }
   scm { url.set("https://github.com/deweyou/cubekit") }
  }
 }
 publishing.repositories { maven { name="localStaging"; url=uri(rootProject.projectDir.resolve("../../dist/maven")) } }
}
