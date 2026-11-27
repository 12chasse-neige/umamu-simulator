package services.accounts.api

import cats.effect.IO
import io.circe.{Decoder, Encoder}
import io.circe.generic.semiauto.{deriveDecoder, deriveEncoder}
import java.sql.Connection
import services.accounts.objects.AccountProfile
import services.accounts.tables.AccountTable.AccountTable
import services.accounts.utils.AccountCredentials
import services.system.api.{APIMessage, ApiFailure}

final case class LoginAccountMessage(username: String, password: String) extends APIMessage[AccountProfile]:
  override def plan(connection: Connection): IO[AccountProfile] =
    val name = AccountCredentials.normalized(username)
    val invalid = ApiFailure(401, "Username or password is incorrect.")
    for
      _ <- AccountCredentials.validate(name, password).adaptError { case _: ApiFailure => invalid }
      digest <- AccountTable.findDigest(connection, name)
      verified <- AccountCredentials.verify(password, digest)
      _ <- IO.raiseUnless(verified)(invalid)
    yield AccountProfile(name)

object LoginAccountMessage:
  given Decoder[LoginAccountMessage] = deriveDecoder
  given Encoder[LoginAccountMessage] = deriveEncoder
