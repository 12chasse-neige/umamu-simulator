package services.accounts.tables.AccountTable

import cats.effect.IO
import java.sql.Connection
import scala.util.Using

object AccountTableInitializer:
  private val createSql =
    """CREATE TABLE IF NOT EXISTS accounts (
      |  username TEXT PRIMARY KEY NOT NULL,
      |  salt BLOB NOT NULL,
      |  password_hash BLOB NOT NULL
      |)""".stripMargin

  def initialize(connection: Connection): IO[Unit] =
    IO.blocking(Using.resource(connection.createStatement())(_.executeUpdate(createSql))).void
