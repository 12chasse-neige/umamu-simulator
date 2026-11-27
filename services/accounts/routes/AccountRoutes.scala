package services.accounts.routes

import services.accounts.api.{LoginAccountMessage, RegisterAccountMessage}
import services.accounts.objects.AccountProfile
import services.system.routes.APIMessageRouter

object AccountRoutes:
  val apiMessages = List(
    APIMessageRouter.register[RegisterAccountMessage, AccountProfile](classOf[RegisterAccountMessage]),
    APIMessageRouter.register[LoginAccountMessage, AccountProfile](classOf[LoginAccountMessage])
  )
