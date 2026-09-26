import java.util.Properties

fun localProperty(key: String): String? {
    val file = rootProject.file("local.properties")
    if (!file.exists()) return null
    return Properties().apply { file.inputStream().use(::load) }.getProperty(key)
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.democracy.kr.democracy"
    // flutter_secure_storage 11 compiles against Android 37 and requires its
    // dependents to as well; Flutter 3.44's default is still 36.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Confirmed application ID. `flutter create --org com.democracy.kr` seeds
        // this as "<org>.<project-name>"; the trailing project segment is dropped
        // here so the shipped identifier matches the reverse-DNS of the service
        // domain. Kept intentionally distinct from `namespace` above, which stays
        // on the generated value so the Kotlin source package need not move.
        applicationId = "com.democracy.kr"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Kakao's redirect scheme is kakao<native app key>. Not a secret, but
        // per environment: pass -PKAKAO_NATIVE_KEY=… or set it in
        // android/local.properties.
        manifestPlaceholders["kakaoNativeKey"] =
            (project.findProperty("KAKAO_NATIVE_KEY") as String?)
                ?: localProperty("KAKAO_NATIVE_KEY")
                ?: ""
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
