import db_sqlite, httpClient, options, asyncdispatch, parseopt, os, strutils
import httpbeast
import tg, core

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


setupTables(db)
echo "DB: users: ", countUsers(db), ", sums: ", countSums(db)

let me = bot.getMe()
echo "TG: starting as @", me.username.get(), " aka ", me.first_name, " #", me.id


proc onUpdate(update: Update) =
  echo update
  let msg = update.message
  if msg.text.isSome:
    let f = msg.`from`.get()
    let user = findOrAddUser(db, f.id, f.first_name, f.last_name, f.username)
    let text = msg.text.get()

    if text.startsWith("/cancel"):
      echo "cancel"
    elif text.startsWith("/use"):
      echo "use"
    else:
      var value = try: some(parseInt(text)) except ValueError: none(int)
      if value.isSome:
        updateUserSum(db, user.id, user.curSumName, int64(value.get()))
      else:
        echo "unknown ", text


bot.startPollingThread(60, onUpdate, allowedUpdates = {UTMessage})


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
