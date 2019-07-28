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


proc answer(bot: TGBot, user: core.User, text: string) =
  discard bot.sendMessage(user.id, text)

proc onUpdate(bot: TGBot, update: Update) =
  let msg = update.message
  if msg.text.isSome:
    let f = msg.`from`.get()
    let user = findOrAddUser(db, f.id, f.first_name, f.last_name, f.username)
    let text = msg.text.get()

    if text.startsWith("/start") or text.startsWith("/help"):
      echo "start"

    elif text.startsWith("/cancel"):
      if user.lastSum.isSome:
        let sum = user.lastSum.get()
        let newValue = updateUserSum(db, user.id, sum.name, -sum.delta)
        answer(bot, user, "Отменил, теперь\n" & sum.name & ": " & $newValue)
      else:
        answer(bot, user, "Отменять пока нечего.")

    elif text.startsWith("/use "):
      let sumName = text[5 .. ^1].strip()
      changeUserCurSum(db, user.id, sumName)
      let sumValue = findSumValue(db, user.id, sumName)
      let strValue = if sumValue.isSome: $sumValue.get() else: "<пусто>"
      answer(bot, user, "Переключился на\n" & sumName & ": " & strValue)

    elif text.startsWith("/"):
      answer(bot, user, "Не знаю такой команды.")

    else:
      let lines = text.split('\n', maxSplit = 2) # lines after first are ignored and may be used as comment
      let parts = lines[0].rsplit(" ", maxSplit = 2)
      let delta = try: some(int64(parseInt(parts[^1]))) except ValueError: none(int64)
      let sumName = if parts.len == 1: user.curSumName else: parts[0]
      if delta.isSome:
        let newValue = updateUserSum(db, user.id, sumName, delta.get())
        answer(bot, user, sumName & ": " & $newValue)
      else:
        answer(bot, user, "Не понял.")


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
