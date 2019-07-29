import db_sqlite, strutils, times, options, sequtils

type
  LastSum = object
    name*: string
    delta*: int64
  User* = object
    id*: int64
    firstName*: string
    lastName*: Option[string]
    username*: Option[string]
    curSumName*: string
    lastSum*: Option[LastSum]
    createdAt*: DateTime

  Sum* = object
    userId*: int64
    name*: string
    value*: int64
    createdAt*: DateTime
    updatedAt*: DateTime

template inTransaction(db: DBConn, statements: untyped) =
  var ok = true
  db.exec(sql"BEGIN")
  try:
    statements
  except:
    ok = false
    raise
  finally:
    if ok:
      db.exec(sql"COMMIT")
    else:
      db.exec(sql"ROLLBACK")

template addOptArg(values: string, args: seq[string], optArg: Option[untyped]) =
  if optArg.isSome:
    values &= (if len(values) == 0: "?" else: ", ?")
    args &= $(optArg.get())
  else:
    values &= (if len(values) == 0: "NULL" else: ", NULL")

proc userFromRow(row: seq[string]): User =
  let lastSum = if row[6] == "": none(LastSum)
    else: some(LastSum(name: row[5], delta: parseInt(row[6])))
  return User(
    id: parseInt(row[0]),
    firstName: row[1],
    lastName: if row[2] == "": none(string) else: some(row[2]),
    username: if row[3] == "": none(string) else: some(row[3]),
    curSumName: row[4],
    lastSum: lastSum,
    createdAt: parse(row[7], "yyyy-MM-dd HH:mm:ss", zone = utc())
  )

proc sumFromRow(row: seq[string]): Sum =
  return Sum(
    userId: int64(parseInt(row[0])),
    name: row[1],
    value: int64(parseInt(row[2])),
    createdAt: parse(row[3], "yyyy-MM-dd HH:mm:ss", zone = utc()),
    updatedAt: parse(row[4], "yyyy-MM-dd HH:mm:ss", zone = utc())
  )

proc setupTables*(db: DBConn) =
  db.exec(sql"""
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT,
    username TEXT,
    cur_sum_name TEXT NOT NULL default 'default',
    last_sum_name TEXT,
    last_sum_delta INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    CHECK ((last_sum_name IS NULL) = (last_sum_delta IS NULL)),
    CHECK (first_name != ''),
    CHECK (last_name != '')
  )""")
  db.exec(sql"""
  CREATE TABLE IF NOT EXISTS sums (
    user_id INTEGER NOT NULL,
    name TEXT NOT NULL DEFAULT 'default',
    value INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, name)
  )""")

proc countUsers*(db: DbConn): int =
  return parseInt(db.getValue(sql"SELECT count(*) FROM users"))

proc countSums*(db: DbConn): int =
  return parseInt(db.getValue(sql"SELECT count(*) FROM sums"))

proc findOrAddUser*(db: DbConn, id: int64, firstName: string, lastName,
    username: Option[string]): User =
  inTransaction(db):
    let row = db.getRow(sql"SELECT * FROM users WHERE id = ?", id)
    if row[0] != "":
      return userFromRow(row)
    else:
      var values = "?, ?"
      var args = @[$id, firstName]
      addOptArg(values, args, lastName)
      addOptArg(values, args, username)
      db.exec(sql("INSERT INTO users (id, first_name, last_name, username) VALUES (" &
          values & ")"), args)
      return userFromRow(db.getRow(sql"SELECT * FROM users WHERE id = ?", id))

proc findSumValue*(db: DBConn, userId: int64, sumName: string): Option[int64] =
  let strValue = db.getValue(sql"""
    SELECT value FROM sums WHERE user_id = ? AND name = ?
    """, userId, sumName)
  if strValue == "":
    return none(int64)
  else:
    return some(int64(parseInt(strValue)))

proc updateUserSum*(db: DBConn, userId: int64, sumName: string,
    delta: int64): int64 =
  inTransaction(db):
    db.exec(sql"""
      INSERT INTO sums (user_id, name, value) VALUES (?, ?, ?)
      ON CONFLICT(user_id, name)
      DO UPDATE SET value = CAST(value + excluded.value AS INT), updated_at = CURRENT_TIMESTAMP
      """, userId, sumName, delta)
    db.exec(sql"""
      UPDATE users SET last_sum_name = ?, last_sum_delta = ? WHERE id = ?
      """, sumName, delta, userId)
    return findSumValue(db, userId, sumName).get()

proc changeUserCurSum*(db: DBConn, userId: int64, sumName: string) =
  db.exec(sql"UPDATE users SET cur_sum_name = ? WHERE id = ?", sumName, userId)

proc removeUserSum*(db: DBConn, userId: int64, sumName: string): bool =
  inTransaction(db):
    db.exec(sql"""
      UPDATE users SET last_sum_name = NULL, last_sum_delta = NULL
      WHERE id = ? AND last_sum_name = ?
      """, userId, sumName)
    let numRows = db.execAffectedRows(sql"""
      DELETE FROM sums WHERE user_id = ? AND name = ?
      """, userId, sumName)
    return numRows > 0

proc findUserSums*(db: DBConn, userId: int64): seq[Sum] =
  return db.getAllRows(sql"""
    SELECT * FROM sums WHERE user_id = ? ORDER BY created_at
    """, userId).map(sumFromRow)
