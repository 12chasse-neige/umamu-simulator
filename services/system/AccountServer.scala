package services.system

import cats.effect.{IO, IOApp, Resource}
import cats.effect.unsafe.IORuntime
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.nio.file.Path
import java.util.concurrent.Executors
import services.accounts.routes.AccountRoutes
import services.accounts.tables.AccountTable.AccountTableInitializer
import services.system.routes.APIMessageRouter
import services.system.utils.Database

object AccountServer extends IOApp.Simple:
  override def run: IO[Unit] =
    val file = Path.of(sys.env.getOrElse("UMAMU_ACCOUNT_DB", "data/accounts.sqlite3"))
    val port = sys.env.getOrElse("UMAMU_ACCOUNT_PORT", "8765").toInt
    val database = Database.connect(file)
    val workers = Resource.make(IO(Executors.newFixedThreadPool(4)))(pool => IO(pool.shutdownNow()).void)
    val server = workers.flatMap { pool =>
      Resource.make(IO.blocking(HttpServer.create(new InetSocketAddress("127.0.0.1", port), 16)))(
        server => IO.blocking(server.stop(0))
      ).evalTap { server =>
        IO {
          server.setExecutor(pool)
          server.createContext("/api/", APIMessageRouter.handler(AccountRoutes.apiMessages, database)(using runtime))
          server.start()
        }
      }
    }
    database.use(AccountTableInitializer.initialize) *>
      server.use(server => IO.println(s"Accounts listening on http://127.0.0.1:${server.getAddress.getPort}") *> IO.never)
