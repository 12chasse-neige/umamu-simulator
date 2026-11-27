package services.system.utils

import cats.effect.{IO, Resource}
import java.nio.file.{Files, Path}
import java.sql.{Connection, DriverManager}
import scala.util.Using

private[system] object Database:
  def connect(file: Path): Resource[IO, Connection] =
    Resource.fromAutoCloseable(IO.blocking {
      Files.createDirectories(file.toAbsolutePath.getParent)
      DriverManager.getConnection(s"jdbc:sqlite:${file.toAbsolutePath}")
    }).evalTap { connection =>
      IO.blocking {
        Using.resource(connection.createStatement())(_.execute("PRAGMA busy_timeout = 4000"))
      }.void
    }
