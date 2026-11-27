ThisBuild / scalaVersion := "3.3.6"

lazy val accounts = (project in file("."))
  .settings(
    name := "umamu-accounts",
    Compile / unmanagedSourceDirectories := Seq(baseDirectory.value / "services"),
    Compile / run / fork := true,
    Compile / mainClass := Some("services.system.AccountServer"),
    libraryDependencies ++= Seq(
      "org.typelevel" %% "cats-effect" % "3.6.3",
      "io.circe" %% "circe-generic" % "0.14.14",
      "io.circe" %% "circe-parser" % "0.14.14",
      "org.xerial" % "sqlite-jdbc" % "3.50.3.0"
    )
  )
