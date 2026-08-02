import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = file(System.getProperty("user.home") + "/.cryptkeep-signing/key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.eerie.cryptkeep"
    compileSdk = flutter.compileSdkVersion
    // NDK 28 aligns native libraries to 16 KB memory pages by default, which
    // Google Play now requires. The Flutter default (NDK 27) does not, and Play
    // rejects the release with a 16 KB page size error.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.eerie.cryptkeep"
        // Android 10+. Required by flutter_autofill_service (the autofill
        // service API the app relies on is not available below SDK 29).
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            ndk {
                debugSymbolLevel = "NONE"
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

dependencies {
    // Required by flutter_autofill_service: its FlutterAutofillService.onCreate
    // casts the tinylog provider to its own DynamicLevelLoggingProvider, which
    // is registered from this module's resources/META-INF/services.
    implementation("org.tinylog:tinylog-api:2.7.0")
    implementation("org.tinylog:tinylog-impl:2.7.0")
    implementation("org.tinylog:slf4j-tinylog:2.7.0")

    // Passkeys (PasskeyProviderService). Declared directly rather than leaned
    // on via flutter_autofill_service, which happens to pull the same library.
    implementation("androidx.credentials:credentials:1.5.0")
}

flutter {
    source = "../.."
}
