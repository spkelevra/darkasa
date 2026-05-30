import java.util.Properties

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { input ->
        localProperties.load(input)
    }
}

val flutterRoot = localProperties.getProperty("flutter.sdk") ?: throw GradleException(
    "Flutter SDK not found. Define location with flutter.sdk in the local.properties file."
)

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

// Using apply plugin for AGP 7.x compatibility if plugins block fails, 
// but modern Flutter usually handles the plugins block fine with AGP 7.4+
plugins {
    id("com.android.application")
    id("kotlin-android")
    // Use the standard flutter gradle plugin ID
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.darkasa" // REPLACE WITH YOUR PACKAGE NAME
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.example.darkasa" // REPLACE WITH YOUR PACKAGE NAME
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.9.22")
}
