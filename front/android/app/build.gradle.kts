import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase: google-services.json 처리 (Android/Kotlin/Flutter 플러그인 뒤)
    id("com.google.gms.google-services")
}

// Release 서명용 key.properties (gitignore). 있으면 release 서명, 없으면 release 빌드는 명시적 실패(하단).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseSigning = keystorePropertiesFile.exists() &&
    !(keystoreProperties["storePassword"] as String?).isNullOrBlank()

android {
    namespace = "com.fury.pokemoncardapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // iOS Bundle ID / Firebase(pokefolio-2e680) 와 동일하게 맞춤. 출시 후 변경 금지.
        applicationId = "com.fury.pokemoncardapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // release keystore 가 있을 때만 생성. 없으면 release buildType signingConfig=null (debug 폴백 안 함).
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // release keystore 있으면 그걸로 서명, 없으면 서명 안 함(null) — debug 키 폴백 절대 금지.
            // keystore 없이 release/bundle 빌드 시 하단 taskGraph 체크가 명시적으로 실패시킴.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
            // R8 누락클래스 규칙(MLKit 다국어 인식기 미사용 경고 억제)
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// release/appbundle 빌드인데 release keystore 가 없으면 명시적 실패 (debug 키로 release 서명되는 사고 방지)
gradle.taskGraph.whenReady {
    val isReleaseBuild = allTasks.any { t ->
        val n = t.name
        n.contains("Release") && (n.startsWith("assemble") || n.startsWith("bundle"))
    }
    if (isReleaseBuild && !hasReleaseSigning) {
        throw GradleException(
            "Release 빌드에 release keystore 가 없습니다. front/android/key.properties + keystore 설정 필요. " +
            "debug 키 폴백 금지 — release AAB 는 release keystore 로만 서명되어야 합니다."
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}
