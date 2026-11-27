package services.accounts.objects

import io.circe.{Decoder, Encoder}
import io.circe.generic.semiauto.{deriveDecoder, deriveEncoder}

final case class AccountProfile(username: String)

object AccountProfile:
  given Decoder[AccountProfile] = deriveDecoder
  given Encoder[AccountProfile] = deriveEncoder
