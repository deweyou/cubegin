plugins {
 id("com.android.library") version "8.9.1"
 id("org.jetbrains.kotlin.android") version "2.1.20"
}
android {
 namespace="io.github.deweyou.consumer"
 compileSdk=35
 defaultConfig { minSdk=23 }
 compileOptions { sourceCompatibility=JavaVersion.VERSION_17;targetCompatibility=JavaVersion.VERSION_17 }
 kotlinOptions { jvmTarget="17" }
 sourceSets.getByName("test").resources.srcDir("../../fixtures")
 testOptions.unitTests.all { it.jvmArgs("-Djna.library.path="+projectDir.resolve("../../target/release").absolutePath) }
}
dependencies {
 implementation("io.github.deweyou:cubegin:0.1.0")
 testImplementation("junit:junit:4.13.2")
 testImplementation("org.json:json:20250107")
 testRuntimeOnly("net.java.dev.jna:jna:5.17.0@jar")
}
