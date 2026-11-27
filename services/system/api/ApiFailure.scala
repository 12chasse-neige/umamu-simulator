package services.system.api

final case class ApiFailure(status: Int, detail: String) extends RuntimeException(detail)
