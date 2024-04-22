open Cobol_common

type sql_token = 
  | Sql_instr of string
  | Sql_var of variable
  | Sql_lit of literal
  | Sql_query of sql_query
  | Sql_equality of sql_equal (*TODO: remove*)
  | Sql_search_condition of sql_where (*TODO: remove*)
and sql_var = string with_loc
and cobol_var_id = string with_loc

and sql_instruction = sql_token list

and variable = 
  | SqlVar of sql_var
  | CobolVar of cobol_var_id

and literal =
  | LiteralVar of variable
  | LiteralNum of string with_loc
  | LiteralStr of string with_loc
  | LiteralDot of string with_loc list

and complex_literal =
  | SqlCompLit of literal
  | SqlCompAs of literal * sql_var (*ex: SMT AS INT*)
  | SqlCompFun of sql_var * sql_op list
  | SqlCompStar

and esql_instuction =
  | At of variable * esql_instuction 
  | Sql of sql_instruction
  | Begin 
  | BeginDeclare
  | EndDeclare
  | StartTransaction
  | Whenever of whenever_condition * whenever_continuation
  | Include of sql_var
  | Connect of connect_syntax
  | Rollback of rb_work_or_tran option * rb_args option
  | Commit of rb_work_or_tran option * bool
  | Savepoint of variable
  | SelectInto of (cobol_var_id) list * sql_select * sql_select_option list (*select and option_select*)
  | DeclareTable of literal * sql_instruction 
  | DeclareCursor of sql_var * sql_instruction
  | Prepare of sql_var * sql_instruction 
  | ExecuteImmediate of sql_instruction
  | ExecuteIntoUsing of sql_var * (cobol_var_id list) option * (cobol_var_id list) option
  | Disconnect of variable option (*db_id*)
  | DisconnectAll
  | Open of sql_var * (cobol_var_id list) option  (*cursor name*)
  | Close of sql_var (*cursor name*)
  | Fetch of sql_instruction * (cobol_var_id) list
  | Insert of table * (value list)
  | Delete of sql_instruction
  | Update of sql_var * sql_update * (update_arg option)
  | Ignore of sql_instruction

and table = 
  | Table of sql_var
  | TableLst of sql_var * (sql_var list)

and value =
  | ValueNull
  | ValueDefault
  | ValueList of literal list

and rb_work_or_tran = Work | Transaction
and rb_args = Release | To of sql_var

and connect_syntax =
  | Connect_to_idby of {
    dbname : literal; 
    db_conn_id : literal option; 
    username : literal; 
    db_data_source : literal;
    password : literal
  }
  | Connect_to of {
    db_data_source : literal; 
    db_conn_id : literal option; 
    username : literal; 
    password : literal option 
  }
  | Connect_using of {db_data_source: literal}

  | Connect_user of{
    username: literal; 
    password: literal; 
    db_conn_id: literal option; 
    db_data_source: literal option
  }
  | Connect_reset of (literal option)

  (*WHENEVER*)
and whenever_condition = 
  | Not_found
  | SqlError
  | SqlWarning

and whenever_continuation = 
  | Continue
  | Perform of sql_var (*A label in cob program*)
  | Goto of sql_var (*TODO doc*)


and update_arg = 
  | WhereCurrentOf of sql_var 
  | UpdateSql of sql_instruction

(*SQL*)
and sql_query = sql_select * sql_select_option list

and sql_select_option =
  | From of sql_var list 
  | Where of sql_where 
  | OrderBy of sql_orderBy

and sql_orderBy = Asc of sql_var | Desc of sql_var

and sql_select = complex_literal list

and sql_update = (sql_equal) list
and sql_equal = sql_var * sql_op

and sql_op = 
  | SqlOpLit of complex_literal
  | SqlOpBinop of (sql_binop * complex_literal * sql_op)
  
and sql_binop = Add | Minus | Times | Or


and sql_where = 
  | WhereConditionOr of sql_where * sql_where
  | WhereConditionAnd of sql_where * sql_where
  | WhereConditionNot of sql_where
  | WhereConditionCompare of sql_compare

and sql_compare = 
  | CompareQuery of complex_literal * compOperator * sql_instruction
  | CompareLit of complex_literal * compOperator * complex_literal

and compOperator = Less | Great | LessEq | GreatEq | EqualComp | Diff 

(*COMPARE*)
(*WIP do not work*)
let rec compare a b = 
  match (a, b) with
(*   | (Sql (i1), Sql (i2)) -> Stdlib.compare i1 i2 *)
  | (BeginDeclare, BeginDeclare) -> 0
  | (EndDeclare, EndDeclare) -> 0
  | (Whenever(conda, konta), Whenever(condb, kontb)) -> 
    compare_whenever_condtion conda condb + compare_whenever_continuation konta kontb
  |_ -> 1
and compare_whenever_condtion a b = 
  match(a,b) with
  | (Not_found, Not_found) -> 0
  | (SqlError, SqlError) -> 0
  | (SqlWarning, SqlWarning) -> 0
  | _ -> 1

and compare_whenever_continuation a b =
  match (a,b) with
  | (Continue, Continue) -> 0  
  | (Perform labela, Perform labelb) when labela == labelb-> 0 
  | (Goto stmt_labela, Goto stmt_labelb) when stmt_labela==stmt_labelb -> 0
  | _ -> 1

(*PRETTY PRINTER*)

let rec pp fmt x = Format.fprintf fmt "EXEC SQL %a END-EXEC\n" pp_esql x

and pp_esql fmt x = 
  match x with
  | At (v, instr) -> Format.fprintf fmt "AT %a %a" pp_var v pp_esql instr
  | Sql instr -> pp_sql fmt instr 
  | Begin -> Format.fprintf fmt "BEGIN"
  | BeginDeclare -> Format.fprintf fmt "BEGIN DECLARE SECTION"
  | EndDeclare -> Format.fprintf fmt "END DECLARE SECTION"
  | StartTransaction -> Format.fprintf fmt "START TRANSACTION"
  | Whenever (c, k) -> 
    Format.fprintf fmt "WHENEVER %a %a" 
    pp_whenever_condtion c 
    pp_whenever_continuation k
  | Include i -> Format.fprintf fmt "INCLUDE %s" i.payload
  | Connect c -> Format.fprintf fmt "CONNECT %a" pp_connect c
  | Rollback (rb_work_or_tran, rb_args) ->
    Format.fprintf fmt "ROLLBACK %a %a" 
    pp_some_rb_work_or_tran rb_work_or_tran
    pp_rb_args rb_args
  | Commit(rb_work_or_tran, bool) -> 
    let s= match bool with
      | true -> "RELEASE"
      | false -> ""
    in
    Format.fprintf fmt "COMMIT %a %s" 
    pp_some_rb_work_or_tran rb_work_or_tran
    s
  | Savepoint s -> Format.fprintf fmt "SAVEPOINT %a" pp_var s
  | SelectInto (into, sql, sql2) -> Format.fprintf fmt "SELECT %a INTO %a %a" 
    pp_select_lst sql
    pp_cob_lst into
    pp_select_options_lst sql2
  | DeclareTable (var, sql) -> Format.fprintf fmt "DECLARE %a TABLE %a" pp_lit var pp_sql sql
  | DeclareCursor (var, sql) -> Format.fprintf fmt "DECLARE %s CURSOR FOR %a" var.payload pp_sql sql
  | Prepare (str, sql) -> Format.fprintf fmt "PREPARE %s FROM %a" str.payload pp_sql sql
  | ExecuteImmediate sql -> Format.fprintf fmt "EXECUTE IMMEDIATE %a" pp_sql sql
  | ExecuteIntoUsing (var, into, using) -> 
    Format.fprintf fmt "EXECUTE %s %a %a" 
    var.payload 
    pp_some_cob_lst (into, "INTO")
    pp_some_cob_lst (using, "USING")

  | Disconnect sdbname -> Format.fprintf fmt "DISCONNECT %a" pp_some_var (sdbname, "")
  | DisconnectAll -> Format.fprintf fmt "DISCONNECT ALL"
  | Open (cursor, lst) -> Format.fprintf fmt "OPEN %s %a" cursor.payload pp_some_cob_lst (lst, "USING")
  | Close cursor -> Format.fprintf fmt "CLOSE %s" cursor.payload
  | Fetch (sql, var) -> Format.fprintf fmt "FETCH %a INTO %a" 
    pp_sql sql
    pp_cob_lst var
  | Insert (tab, v) -> Format.fprintf fmt "INSERT INTO %a VALUES (%a)" pp_table tab pp_value v
  | Delete sql -> Format.fprintf fmt "DELETE %a" pp_sql sql
  | Update (table, equallst, swhere) -> 
    Format.fprintf fmt "UPDATE %s SET %a %a" 
    table.payload 
    pp_sql_update equallst 
    pp_where_arg swhere
  | Ignore lst -> Format.fprintf fmt "IGNORE %a" pp_sql lst

and pp_table fmt x =
  match x with 
  | Table t -> Format.fprintf fmt "%s" t.payload
  | TableLst (t, lst) -> 
      let pp_aux fmt x = List.iter (Format.fprintf fmt "%s") (List.map(Srcloc.payload) x)
    in
    Format.fprintf fmt "%s(%a)" t.payload pp_aux lst

and pp_value fmt x = List.iter (Format.fprintf fmt "%a" pp_one_value) x 
and pp_one_value fmt x =
  match x with
  | ValueDefault -> Format.fprintf fmt "DEFAULT"
  | ValueNull -> Format.fprintf fmt "NULL"
  | ValueList l -> Format.fprintf fmt "(%a)" pp_list_lit l

and pp_where_arg fmt = function
| Some x -> (
  match x with
  | WhereCurrentOf swhere -> Format.fprintf fmt "WHERE CURRENT OF %s" swhere.payload 
  | UpdateSql sql -> pp_sql fmt sql)
| None -> Format.fprintf fmt ""

and pp_sql_update_aux fmt (var, op) = 
  Format.fprintf fmt "%s = %a\n" var.payload pp_sql_op op

and pp_sql_update fmt x = 
  List.iter (pp_sql_update_aux fmt) x  

and pp_sql_op fmt = function
| SqlOpBinop (op, sql1, sql2) -> Format.fprintf fmt "%a %s %a" pp_complex_literal sql1 (pp_binop op) pp_sql_op sql2
| SqlOpLit (l) -> Format.fprintf fmt "%a" pp_complex_literal l

and pp_sql_some_condition fmt = function
| Some s -> Format.fprintf fmt "WHERE %a" pp_sql_condition s 
| None -> Format.fprintf fmt ""

and pp_sql_condition fmt = function 
| WhereConditionAnd (s1, s2) -> Format.fprintf fmt "%a AND %a" pp_sql_condition s1 pp_sql_condition s2
| WhereConditionOr (s1, s2) -> Format.fprintf fmt "%a OR %a" pp_sql_condition s1 pp_sql_condition s2
| WhereConditionNot s -> Format.fprintf fmt "Not %a" pp_sql_condition s
| WhereConditionCompare c -> 
  let rec pp_compare fmt = function 
    | CompareLit (l1, c, l2) -> Format.fprintf fmt "%a %s %a" pp_complex_literal l1 (comp_op_to_string c) pp_complex_literal l2
    | CompareQuery (l1, c, s) -> Format.fprintf fmt "%a %s %a" pp_complex_literal l1 (comp_op_to_string c) pp_sql s

    and comp_op_to_string = function 
    | Less -> "<" 
    | Great -> ">"
    | LessEq -> "<="
    | GreatEq -> ">="
    | EqualComp -> "="
    | Diff -> "<>"
  in
  Format.fprintf fmt "%a" pp_compare c



and pp_complex_literal fmt = function
| SqlCompLit v -> Format.fprintf fmt "%a" pp_lit v
| SqlCompAs (l, v)  ->  Format.fprintf fmt "%a AS %s" pp_lit l v.payload 
| SqlCompFun (funName, args) -> 
  let pp_args fmt lst = List.iter(Format.fprintf fmt "%a," pp_sql_op) lst in
  Format.fprintf fmt "%s(%a)" funName.payload pp_args args 
| SqlCompStar -> Format.fprintf fmt "*"

and pp_binop = function
| Add -> "+"
| Minus -> "-"
| Times -> "*"
| Or -> "||"
and pp_some_cob_lst fmt = function
| (Some x, s) -> Format.fprintf fmt "%s %a" s pp_cob_lst x
| (None, _) -> Format.fprintf fmt ""
and pp_cob_lst fmt x =  List.iter (Format.fprintf fmt ":%s, ") (List.map(Srcloc.payload) x)


and pp_some_rb_work_or_tran fmt = function
  | Some p ->  pp_rb_work_or_tran fmt p
  | None -> Format.fprintf fmt "" 
  
and pp_rb_work_or_tran fmt = function
  | Work -> Format.fprintf fmt "WORK"
  | Transaction -> Format.fprintf fmt "TRANSACTION"

and pp_rb_args fmt = function
  | Some Release -> Format.fprintf fmt "RELEASE"
  | Some To (variable) -> Format.fprintf fmt "TO SAVEPOINT %s" variable.payload
  | None -> Format.fprintf fmt ""

and pp_connect fmt c =
  match c with
  | Connect_to_idby {dbname ;db_conn_id ;username ;db_data_source; password} ->
    Format.fprintf fmt "TO %a %a USER %a USING %a IDENTIFIED BY %a"
    pp_lit dbname 
    pp_some_lit (db_conn_id, "AS" )
    pp_lit username 
    pp_lit db_data_source
    pp_lit password

  | Connect_to {db_data_source ;db_conn_id ;username ;password} ->
    Format.fprintf fmt "TO %a %a USER %a %a"
    pp_lit db_data_source 
    pp_some_lit (db_conn_id, "AS" )
    pp_lit username 
    pp_some_lit (password, "USING" )

  | Connect_using {db_data_source} -> 
    Format.fprintf fmt "USING %a"
    pp_lit db_data_source 

  | Connect_user{username; password; db_conn_id; db_data_source} ->
    Format.fprintf fmt "%a IDENTIFIED BY %a %a %a"
    pp_lit username 
    pp_lit password 
    pp_some_lit (db_conn_id, "AT" )
    pp_some_lit (db_data_source, "USING" )

  | Connect_reset (name)-> 
    Format.fprintf fmt "RESET%a" pp_some_lit (name, " " )

and pp_whenever_condtion fmt x =
  match x with
  | Not_found -> Format.fprintf fmt "NOT FOUND"
  | SqlError-> Format.fprintf fmt "SQLERROR"
  | SqlWarning-> Format.fprintf fmt "SQLWARNING"

and pp_whenever_continuation fmt x =
  match x with
  | Continue -> Format.fprintf fmt "CONTINUE"
  | Perform (label) -> Format.fprintf fmt "PERFORM %s" label.payload
  | Goto (stmt_label) -> Format.fprintf fmt "GOTO %s" stmt_label.payload

and pp_some_sql fmt = function
  | Some p ->  pp_sql fmt p
  | None -> Format.fprintf fmt "" 
and  pp_sql fmt x =  Format.fprintf fmt "sql(%a)" pp_sql_rec x

and pp_sql_rec fmt x =  List.iter (Format.fprintf fmt "[%a]" pp_one_token) x
and pp_one_token fmt = function
| Sql_instr(s) -> Format.fprintf fmt "%s" s
| Sql_var(c) -> Format.fprintf fmt ":%a" pp_var c
| Sql_lit l -> Format.fprintf fmt ":%a" pp_lit l
| Sql_query s -> Format.fprintf fmt "%a" pp_sql_query s
| Sql_equality e -> Format.fprintf fmt "%a" pp_sql_update_aux e
| Sql_search_condition c -> Format.fprintf fmt "%a" pp_sql_condition c

and pp_sql_query fmt (s, o) = 
  Format.fprintf fmt "SELECT %a %a" 
  pp_select_lst s 
  pp_select_options_lst o

and pp_select_options_lst fmt lst =
  let pp_one_option fmt = function 
  | From f -> pp_from fmt f
  | Where w -> pp_sql_condition fmt w
  | OrderBy ob -> pp_orderBy fmt ob
  in
  List.iter (Format.fprintf fmt "%a" pp_one_option) lst

and pp_from fmt f= 
  let pp_aux fmt x = List.iter (Format.fprintf fmt "%s") (List.map(Srcloc.payload) x)
  in
  Format.fprintf fmt "FROM %a" pp_aux f

and pp_orderBy fmt = function
  | Asc v -> Format.fprintf fmt "ORDER BY %s ASC" v.payload 
  | Desc v -> Format.fprintf fmt "ORDER BY %s DESC" v.payload 

and pp_select_lst fmt l = List.iter (Format.fprintf fmt "%a, " pp_complex_literal) l

and pp_list_var fmt l = List.iter (Format.fprintf fmt "%a " pp_var) l
and pp_some_var fmt (x, s) =
  match x with
  | Some v -> Format.fprintf fmt "%s %a" s pp_var v
  | None -> Format.fprintf fmt ""
and pp_var fmt x =
  match x with
  | SqlVar v -> Format.fprintf fmt "%s" v.payload
  | CobolVar c -> Format.fprintf fmt ":%s" c.payload

and pp_some_lit fmt (x, s)= 
match x with
| Some v -> Format.fprintf fmt "%s %a" s pp_lit v
| None -> Format.fprintf fmt ""

and pp_list_lit fmt x = List.iter (Format.fprintf fmt "%a " pp_lit) x


and pp_lit fmt x = 
  match x with
  | LiteralNum n -> Format.fprintf fmt "%s" n.payload
  | LiteralStr n -> Format.fprintf fmt "%s" n.payload
  | LiteralVar n -> (Format.fprintf fmt "%a" pp_var n)
  | LiteralDot lst -> List.iter (Format.fprintf fmt ".%s") (List.map(Srcloc.payload) lst)