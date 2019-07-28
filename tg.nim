import options, json, httpClient, strutils, sequtils

type
  TGBot* = object
    token: string
    proxy: Proxy
    client: HttpClient

  Response* = object
    ok: bool
    result: JsonNode

  Result* = object of RootObj

  User* = object
    id*: int64                     # Unique identifier for this user or bot
    is_bot*: bool                  # True, if this user is a bot
    first_name*: string            # User‘s or bot’s first name
    last_name*: Option[string]     # User‘s or bot’s last name
    username*: Option[string]      # User‘s or bot’s username
    language_code*: Option[string] # IETF language tag of the user's language

  ChatType* = enum
    CTPrivate = "private"
    CTGroup = "group"
    CTSupergroup = "supergroup"
    CTChannel = "channel"
  Chat* = object
    id: int64                  # Unique identifier for this chat.
    `type`: ChatType # Type of chat, can be either “private”, “group”, “supergroup” or “channel”
    title: Option[string]      # Title, for supergroups, channels and group chats
    username: Option[string] # Username, for private chats, supergroups and channels if available
    first_name: Option[string] # First name of the other party in a private chat
    last_name: Option[string]  # Last name of the other party in a private chat
                               # ...

  Message* = object
    message_id*: int64    # Unique message identifier inside this chat
    `from`*: Option[User] # Optional. Sender, empty for messages sent to channels
    date*: int64          # Date the message was sent in Unix time
    chat*: Chat           # Conversation the message belongs to
    text*: Option[string] # For text messages, the actual UTF-8 text of the message
                          # ...

  Update* = object of Result
    update_id*: int64
    message*: Message

  UpdateType* = enum
    UTMessage = "message"
    UTEditedChannelPost = "edited_channel_post"
    UTCallbackQuery = "callback_query"

  ParseMode* = enum
    PMNone = (0, "Off")
    PMMarkdown = (1, "Markdown")
    PMHtml = (2, "HTML")

  OnUpdate* = proc(bot:TGBot, update: Update) {.gcsafe.}
  PollThreadArgs = tuple[interval: int, allowedUpdates: set[UpdateType],
      token: string, proxy: Proxy, onUpdate: OnUpdate]


proc debug(args: varargs[string, `$`]) =
  echo "\27[90m" & args.join(" ") & "\27[0m"

proc newTGBot*(token: string, proxy: Proxy = nil): TGBot =
  let client = newHttpClient(proxy = proxy)
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  return TGBot(token: token, client: client, proxy: proxy)

proc sendRequest*(bot: TGBot, methodName: string,
    params: JsonNode = nil): Response =
  let path = "https://api.telegram.org/bot" & bot.token & "/" & methodName
  # let resp = client.getContent(path)
  let reqBody = if params == nil: "" else: $params
  debug "<", methodName, reqBody
  let resp = bot.client.request(path, httpMethod = HttpPost, body = reqBody)
  let respBody = resp.body()
  debug ">", respBody
  return parseJson(respBody).to(Response)

proc getMe*(bot: TGBot): User =
  return bot.sendRequest("getMe").result.to(User)

proc getUpdates*(bot: TGBot, offset, limit, timeout: int = 0,
    allowedUpdates: set[UpdateType] = {}): seq[Update] =
  var params = %* {
    "offset": offset,
    "limit": limit,
    "timeout": timeout,
    "allowed_updates": toSeq(allowedUpdates)
  }
  return bot.sendRequest("getUpdates", params).result.to(seq[Update])

proc sendMessage*(bot: TGBot, chatId: int64, text: string,
    parseMode: ParseMode = PMNone, disabelWebPagePreview: bool = false,
    disableNotification: bool = false, replyToMessageId: int64 = 0): Message =
  ## chat_id                  Unique identifier for the target chat
  ## text                     Text of the message to be sent
  ## parse_mode               Pass `Markdown` or `HTML`, if you want Telegram apps to show bold, italic, fixed-width text or inline URLs in your bot's message
  ## disable_web_page_preview Disables link previews for links in this message
  ## disable_notification     Sends the message silently. Users will receive a notification with no sound
  ## reply_to_message_id      If the message is a reply, ID of the original message
  ##
  ## TODO:
  ##  chat_id as @username string
  ##  reply_markup InlineKeyboardMarkup or ReplyKeyboardMarkup or ReplyKeyboardRemove or ForceReply
  var params = %* {
    "chat_id": chatId,
    "text": text,
  }
  if parseMode != PMNone: params["parse_mode"] = %* parseMode
  if disabelWebPagePreview: params["disable_web_page_preview"] = %* true
  if disableNotification: params["disable_notification"] = %* true
  if replyToMessageId != 0: params["reply_to_message_id"] = %* replyToMessageId
  return bot.sendRequest("sendMessage", params).result.to(Message)

proc startPoling*(bot: TGBot, interval: int, onUpdate: OnUpdate,
    allowedUpdates: set[UpdateType] = {}) =
  var lastUpdateId = 0
  while true:
    for update in bot.getUpdates(timeout = interval, offset = lastUpdateId + 1,
        allowedUpdates = allowedUpdates):
      if update.update_id > lastUpdateId:
        lastUpdateId = int(update.update_id)
      onUpdate(bot, update)

proc startPollingThread*(bot: TGBot, interval: int, onUpdate: OnUpdate,
    allowedUpdates: set[UpdateType] = {}) =
  var thread = new Thread[PollThreadArgs]
  proc threadFunc(a: PollThreadArgs) {.thread.} =
    let bot = newTGBot(a.token, a.proxy)
    bot.startPoling(a.interval, a.onUpdate, allowedUpdates = a.allowedUpdates)
  createThread(thread[], threadFunc, (interval, allowedUpdates, bot.token,
      bot.proxy, onUpdate))
  GC_ref(thread)

