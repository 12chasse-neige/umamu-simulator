package services.accounts.api

import cats.effect.IO
import io.circe.{Decoder, Encoder}
import io.circe.generic.semiauto.{deriveDecoder, deriveEncoder}
import java.sql.Connection
import services.accounts.objects.AccountProfile
import services.accounts.tables.AccountTable.AccountTable
import services.accounts.utils.AccountCredentials
import services.system.api.{APIMessage, ApiFailure}

final case class RegisterAccountMessage(username: String, password: String) extends APIMessage[AccountProfile]:
  override def plan(connection: Connection): IO[AccountProfile] =
    val name = AccountCredentials.normalized(username)
    for
      _ <- AccountCredentials.validate(name, password)
      digest <- AccountCredentials.create(password)
      (salt, hash) = digest
      created <- AccountTable.insert(connection, name, salt, hash)
      _ <- IO.raiseUnless(created)(ApiFailure(409, "That username is taken."))
    yield AccountProfile(name)

object RegisterAccountMessage:
  given Decoder[RegisterAccountMessage] = deriveDecoder
  given Encoder[RegisterAccountMessage] = deriveEncoder
