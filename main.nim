import db_sqlite, httpClient, options, asyncdispatch, parseopt, os
import httpbeast
import tg

var httpProxyAddr = ""
let token = getEnv("TG_BOT_TOKEN")

if token == "":
  raise newException(Exception, "TG_BOT_TOKEN env variable is missing")

var p = initOptParser(commandLineParams())
while true:
  p.next()
  case p.kind
  of cmdEnd: break
  of cmdShortOption, cmdLongOption:
    if p.key == "http-proxy-addr":
      httpProxyAddr = p.val
  of cmdArgument:
    echo "unexpected argument: ", p.key


let db = open("main.db", "", "", "")

let proxy = if httpProxyAddr == "": nil else: newProxy(url = httpProxyAddr)
let bot = newTGBot(token, proxy)


db.exec(sql"""
CREATE TABLE IF NOT EXISTS test_tbl (
  id    INTEGER PRIMARY KEY,
  text  TEXT,
  count INT
)""")
# db.exec(sql"INSERT INTO test_tbl VALUES (1, 'qwe', 0), (2, 'asd', 1), (3, 'zxc', 0);")


proc onUpdate(update: Update) =
  echo update
  for r in db.fastRows(sql"SELECT count FROM test_tbl"):
    echo r
bot.startPollingThread(10, onUpdate, allowedUpdates = {UTMessage})

echo bot.getMe()
# echo bot.getUpdates(allowedUpdates = {UTMessage})

proc onRequest(req: Request): Future[void] =
  if req.httpMethod == some(HttpGet):
    case req.path.get()
    of "/":
      echo "start"
      req.send("Hello World")
      # sleep(5000)
      db.exec(sql"UPDATE test_tbl SET count = count + 1")
      for x in db.fastRows(sql"SELECT count FROM test_tbl"):
        echo x
      echo "end"
    else:
      req.send(Http404)

run(onRequest, Settings(port: Port(9003)))
