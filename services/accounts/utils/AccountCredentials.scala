package services.accounts.utils

import cats.effect.IO
import java.security.{MessageDigest, SecureRandom}
import java.util.Locale
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import services.system.api.ApiFailure

private[accounts] object AccountCredentials:
  private val random = new SecureRandom()
  private val iterations = 600_000
  private val emptySalt = new Array[Byte](16)
  private val emptyHash = new Array[Byte](32)

  private[accounts] def normalized(username: String): String =
    username.trim.toLowerCase(Locale.ROOT)

  private[accounts] def validate(username: String, password: String): IO[Unit] =
    if !username.matches("[a-z0-9_]{3,24}") then
      IO.raiseError(ApiFailure(400, "Use 3–24 letters, digits or underscores for the username."))
    else if password.length < 8 || password.length > 128 then
      IO.raiseError(ApiFailure(400, "Use 8–128 characters for the password."))
    else IO.unit

  private[accounts] def create(password: String): IO[(Array[Byte], Array[Byte])] =
    IO.blocking {
      val salt = new Array[Byte](16)
      random.nextBytes(salt)
      (salt, derive(password, salt))
    }

  private[accounts] def verify(password: String, stored: Option[(Array[Byte], Array[Byte])]): IO[Boolean] =
    IO.blocking {
      val (salt, hash) = stored.getOrElse((emptySalt, emptyHash))
      val matched = MessageDigest.isEqual(derive(password, salt), hash)
      matched && stored.isDefined
    }

  private def derive(password: String, salt: Array[Byte]): Array[Byte] =
    val spec = new PBEKeySpec(password.toCharArray, salt, iterations, 256)
    try SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded
    finally spec.clearPassword()
