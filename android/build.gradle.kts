allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // Aligne tous les greffons sur le même niveau d'API que l'application.
    //
    // Certains greffons figent leur `compileSdk` à une valeur ancienne, alors
    // qu'un de leurs dépendants en exige une plus récente : la compilation
    // s'arrête sur « requires ... version 36 or later », et rien dans le code
    // de l'application ne permet de le corriger.
    //
    // Compiler contre une API récente ne change pas les téléphones visés :
    // c'est `minSdk` qui les détermine, et il n'est pas touché.
    //
    // Enregistré AVANT `evaluationDependsOn`, qui force l'évaluation : après,
    // Gradle refuse tout `afterEvaluate` sur un projet déjà évalué.
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            (ext as? com.android.build.gradle.BaseExtension)?.compileSdkVersion(36)
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
