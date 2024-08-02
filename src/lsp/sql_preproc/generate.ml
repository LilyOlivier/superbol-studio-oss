(**************************************************************************)
(*                                                                        *)
(*  Copyright (c) 2021-2023 OCamlPro SAS                                  *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*  This file is distributed under the terms of the                       *)
(*  OCAMLPRO-NON-COMMERCIAL license.                                      *)
(*                                                                        *)
(**************************************************************************)

open EzCompat
open Types
open Sql_ast

let comment str =
  Generated_type.Added
    { content = [ Generated_type.Comment { content = str } ] }

let generate ~filename ~contents ~cobol_unit sql_statements =
  let linkage_section = comment "" in
  let begin_procedure_division ~loc:_ =
    (* We might want to add something at the begining of PROCEDURE DIVISION ? *)
    [ comment "" ]
  in

  (* split lines and numerotate them *)
  let lines = EzString.split contents '\n' in
  let lines = List.mapi (fun i line -> (filename, i + 1, line)) lines in

  (*string to add at the end of every sql processed*)

  (* The result will be stored in this buffer: *)
  let _final_loc = { filename; line = -1; char = 0 } in

  let error_treatment = ref [] in
  let old_statements = ref [] in
  let cursor_declararation = ref [] in
  let num = ref 0 in

  (*GET FUNCTION*)
  (*TODOOOO*)
  let working_storage_section, new_var_map =
    let ws, nvm = Data_gestion.transform sql_statements filename in
    ( [ comment ">Begin generated WORKING-STORAGE SECTION";
        Generated_type.Added { content = ws };
        comment "> End genererated WORKING-STORAGE SECTION"
      ],
      nvm )
  in

  let end_procedure_division cd =
    (comment "> ESQL CURSOR DECLARATIONS (START)" :: cd)
    @ [ comment "> ESQL CURSOR DECLARATIONS (END)" ]
  in

  let cob_var_id_opt (cob_var : cobolVarId option) =
    match cob_var with
    | Some cob -> Some cob.payload
    | None -> None
  in

  let cob_var_opt = function
    | Some var -> (
      match var with
      | CobVarNotNull cobolVarId -> Some cobolVarId.payload
      | CobVarNullIndicator (var, _) -> Some var.payload )
    | None -> None
  in

  let var_opt = function
    | Some var -> (
      match var with
      | SqlVar sqlVarToken -> Some ("\"" ^ sqlVarToken.payload ^ "\" & x\"00\"")
      | CobolVar cobol_var -> cob_var_opt (Some cobol_var) )
    | None -> None
  in

  let get_length str =
    match Data_gestion.find_opt new_var_map str with
    | Some a -> a.length
    | None -> Sql_typeck.get_length cobol_unit str
  in

  let get_some_cob_var_length (cob_var : cobolVarId option) =
    match cob_var with
    | Some x -> Some (get_length x.payload)
    | None -> None
  in

  let get_some_length var =
    match var with
    | Some (CobolVar (CobVarNotNull cobol_var)) ->
      get_some_cob_var_length (Some cobol_var)
    | _ -> None
  in

  let get_type str =
    match Data_gestion.find_opt new_var_map str with
    | Some a -> a.vartype
    | None -> Sql_typeck.get_type cobol_unit str
  in
  let get_scale str =
    match Data_gestion.find_opt new_var_map str with
    | Some a -> a.scale
    | None -> Sql_typeck.get_scale cobol_unit str
  in
  let get_flags str =
    match Data_gestion.find_opt new_var_map str with
    | Some a -> a.flags
    | None -> Sql_typeck.get_flags cobol_unit str
  in
  let get_ind_addr str =
    match Data_gestion.find_opt new_var_map str with
    | Some a -> a.ind_addr
    | None -> Sql_typeck.get_ind_addr cobol_unit str
  in

  (*GENERATE FUNCTION*)
  let generate_start_end_sql prefix smt =
    let startSql =
      Generated_type.CallStatic
        { prefix; fun_name = "GIXSQLStartSQL"; ref_value = [] }
    in
    let endSql =
      Generated_type.CallStatic
        { prefix; fun_name = "GIXSQLEndSQL"; ref_value = [] }
    in
    let trans_stm = (startSql :: smt) @ [ endSql ] in
    trans_stm
  in

  let generatesql_connect_reset ~prefix ?(d_connection_id = "x\"00\"")
      ?(connection_id_tl = 0) () =
    let fun_name = "GIXSQLConnectReset" in
    let ref_value =
      let prefix = prefix ^ "    " in
      [ Generated_type.Reference { prefix; var = "SQLCA" };
        Generated_type.Reference { prefix; var = d_connection_id };
        Generated_type.Value { prefix; var = string_of_int connection_id_tl }
      ]
    in
    Generated_type.CallStatic { prefix; fun_name; ref_value }
  in

  let generatesql_connect_aux ~prefix ?(data_source = "x\"00\"")
      ?(data_source_tl = 0) ?(d_connection_id = "x\"00\"")
      ?(connection_id_tl = 0) ?(d_dbname = "x\"00\"") ?(dbname_tl = 0)
      ?(d_username = "x\"00\"") ?(username_tl = 0) ?(d_password = "x\"00\"")
      ?(password_tl = 0) () =
    let fun_name = "GIXSQLConnect" in
    let ref_value =
      let prefix = prefix ^ "    " in
      [ Generated_type.Reference { prefix; var = "SQLCA" };
        Generated_type.Reference { prefix; var = data_source };
        Generated_type.Value { prefix; var = string_of_int data_source_tl };
        Generated_type.Reference { prefix; var = d_connection_id };
        Generated_type.Value { prefix; var = string_of_int connection_id_tl };
        Generated_type.Reference { prefix; var = d_dbname };
        Generated_type.Value { prefix; var = string_of_int dbname_tl };
        Generated_type.Reference { prefix; var = d_username };
        Generated_type.Value { prefix; var = string_of_int username_tl };
        Generated_type.Reference { prefix; var = d_password };
        Generated_type.Value { prefix; var = string_of_int password_tl }
      ]
    in
    Generated_type.CallStatic { prefix; fun_name; ref_value }
  in

  let generatesql_connect cs prefix =
    (*TODO: Some of these a unsuported in gixSql -> emit a preproc warning
      list of unsuported connection:
      mode 5 and 6 when named ("AT/AS db_conn_id ")
      mode 4 (ex: CONNECT :DBUSR IDENTIFIED BY :DBPWD)*)
    match cs with
    | Connect_reset lit ->
      [ generatesql_connect_reset ~prefix ?d_connection_id:(var_opt lit)
          ?connection_id_tl:(get_some_length lit) ()
      ]
    | Connect_to_idby { dbname; db_conn_id; db_data_source; username; password }
      ->
      [ generatesql_connect_aux ~prefix ~data_source:db_data_source.payload
          ~data_source_tl:(get_length db_data_source.payload)
          ?d_connection_id:(var_opt db_conn_id)
          ?connection_id_tl:(get_some_length db_conn_id)
          ~d_dbname:dbname.payload
          ~dbname_tl:(get_length dbname.payload)
          ~d_username:username.payload
          ~username_tl:(get_length username.payload)
          ~d_password:password.payload
          ~password_tl:(get_length password.payload)
          ()
      ]
    | Connect_to { db_conn_id; db_data_source; username; password } ->
      [ generatesql_connect_aux ~prefix ~data_source:db_data_source.payload
          ~data_source_tl:(get_length db_data_source.payload)
          ?d_connection_id:(var_opt db_conn_id)
          ?connection_id_tl:(get_some_length db_conn_id)
          ~d_username:username.payload
          ~username_tl:(get_length username.payload)
          ?d_password:(cob_var_id_opt password)
          ?password_tl:(get_some_cob_var_length password)
          ()
      ]
    | Connect_using { db_data_source } ->
      [ generatesql_connect_aux ~prefix ~data_source:db_data_source.payload
          ~data_source_tl:(get_length db_data_source.payload)
          ()
      ]
    | Connect_user { db_conn_id; db_data_source; username; password } ->
      [ generatesql_connect_aux ~prefix
          ?data_source:(cob_var_id_opt db_data_source)
          ?data_source_tl:(get_some_cob_var_length db_data_source)
          ?d_connection_id:(var_opt db_conn_id)
          ?connection_id_tl:(get_some_length db_conn_id)
          ~d_username:username.payload
          ~username_tl:(get_length username.payload)
          ~d_password:password.payload
          ~password_tl:(get_length password.payload)
          ()
      ]
  in

  let generate_whenever ~prefix c k =
    let condition =
      match c with
      | Sql_ast.Not_found_whenever -> Generated_type.Not_found_whenever
      | Sql_ast.SqlError_whenever -> Generated_type.SqlError_whenever
      | Sql_ast.SqlWarning_whenever -> Generated_type.SqlWarning_whenever
    in
    let continuation =
      match k with
      | Sql_ast.Continue -> Generated_type.Continue
      | Sql_ast.Perform x -> Generated_type.Perform x.payload
      | Sql_ast.Goto x -> Generated_type.Goto x.payload
    in
    Generated_type.Error_treatment { prefix; condition; continuation }
  in

  let get_name_cobol_var (cobol_var : cobol_var) =
    match cobol_var with
    | CobVarNotNull c -> c.payload
    | CobVarNullIndicator (c, n) -> c.payload ^ n.payload
  in

  let generate_select_into_rec prefix arg =
    let h = get_name_cobol_var arg in
    let fun_name = "GIXSQLSetResultParams" in
    let ref_value =
      let prefix = prefix ^ "    " in
      [ Generated_type.Value { prefix; var = string_of_int (get_type h) };
        Generated_type.Value { prefix; var = string_of_int (get_length h) };
        Generated_type.Value { prefix; var = string_of_int (get_scale h) };
        Generated_type.Value { prefix; var = string_of_int (get_flags h) };
        Generated_type.Reference { prefix; var = h };
        Generated_type.Reference
          { prefix; var = string_of_int (get_ind_addr h) }
      ]
    in
    Generated_type.CallStatic { prefix; fun_name; ref_value }
  in

  let generate_select_into_one prefix vars ?(at = "x\"00\"") () =
    let size = string_of_int (List.length vars) in
    let fun_name = "GIXSQLExecSelectIntoOne" in
    let ref_value =
      let var_name =
        num := !num + 1;
        "SQ" ^ string_of_int !num
      in
      let prefix = prefix ^ "    " in
      [ Generated_type.Reference { prefix; var = "SQLCA" };
        Generated_type.Reference { prefix; var = at };
        Generated_type.Value { prefix; var = "0" };
        Generated_type.Reference { prefix; var = var_name };
        Generated_type.Value { prefix; var = "0" };
        Generated_type.Value { prefix; var = size }
      ]
    in
    Generated_type.CallStatic { prefix; fun_name; ref_value }
  in

  let generate_select_into prefix vars ?(at = "x\"00\"") () =
    let selects_into_vars = List.map (generate_select_into_rec prefix) vars in
    let selects_into = generate_select_into_one prefix vars ~at () in
    let trans_stm =
      generate_start_end_sql prefix (selects_into_vars @ [ selects_into ])
    in
    trans_stm
  in

  let generate_GIXSQLExec prefix name ?(at = "x\"00\"") () =
    let fun_name = "GIXSQLExec" in
    let ref_value =
      let prefix = prefix ^ "    " in
      [ Generated_type.Reference { prefix; var = "SQLCA" };
        Generated_type.Reference { prefix; var = at };
        Generated_type.Value { prefix; var = "0" };
        Generated_type.Reference { prefix; var = "\"" ^ name ^ "\" & x\"00\"" }
      ]
    in
    Generated_type.CallStatic { prefix; fun_name; ref_value }
  in

  let generate_declare prefix ?(at = "x\"00\"") () =
    let fun_name = "GIXSQLExec" in
    let ref_value =
      let var_name =
        num := !num + 1;
        "SQ" ^ string_of_int !num (*I pray for it to be in the good order*)
      in
      let prefix = prefix ^ "    " in
      [ Generated_type.Reference { prefix; var = "SQLCA" };
        Generated_type.Reference { prefix; var = at };
        Generated_type.Value { prefix; var = "0" };
        Generated_type.Reference { prefix; var = var_name }
      ]
    in
    let declare = Generated_type.CallStatic { prefix; fun_name; ref_value } in

    let trans_stm = generate_start_end_sql prefix [ declare ] in
    trans_stm
  in

  let generate_rollback prefix rb_work_or_tran rb_args ?(at = "x\"00\"") () =
    match (rb_work_or_tran, rb_args) with
    | None, None ->
      generate_start_end_sql prefix
        [ generate_GIXSQLExec prefix "ROLLBACK" ~at () ]
    | _, Some (To _) -> generate_declare prefix ()
    | _ -> [ Generated_type.Todo { prefix } ]
  in

  let generate_commit prefix rb_work_or_tran rb_args ?(at = "x\"00\"") () =
    match (rb_work_or_tran, rb_args) with
    | None, false ->
      generate_start_end_sql prefix
        [ generate_GIXSQLExec prefix "COMMIT" ~at () ]
    | _ -> [ Generated_type.Todo { prefix } ]
  in

  let add_to_cursor_declararation prefix cur ?(at = "x\"00\"") () =
    let adding =
      match cur with
      | DeclareCursorSql (cur_name, _) -> begin
        let fun_name = "GIXSQLCursorDeclare" in
        let ref_value =
          let cursor_name = "\"TSQL003A_" ^ cur_name.payload ^ "\" & x\"00\"" in
          let var_name =
            num := !num + 1;
            "SQ" ^ string_of_int !num (*I pray for it to be in the good order*)
          in
          let prefix = prefix ^ "    " in
          [ Generated_type.Reference { prefix; var = "SQLCA" };
            Generated_type.Reference { prefix; var = at };
            Generated_type.Value { prefix; var = "0" };
            Generated_type.Reference { prefix; var = cursor_name };
            Generated_type.Value { prefix; var = "0" };
            Generated_type.Reference { prefix; var = var_name };
            Generated_type.Value { prefix; var = "0" }
          ]
        in
        [ Generated_type.GotoStatement
            { prefix;
              target =
                "GIXSQL-CI-P-"
                ^ Misc.extract_filename filename
                ^ "-" ^ cur_name.payload
            };
          Generated_type.CallStatic { prefix; fun_name; ref_value }
        ]
      end
      (* GIXSQL GIXSQL-CI-P-TSQL003A-CRSR01.
         GIXSQL     CALL STATIC "GIXSQLCursorDeclare" USING
         GIXSQL         BY REFERENCE SQLCA
         GIXSQL         BY REFERENCE "CONN1" & x"00"
         GIXSQL         BY VALUE 0
         GIXSQL         BY REFERENCE "TSQL003A_CRSR01" & x"00"
         GIXSQL         BY VALUE 0
         GIXSQL         BY REFERENCE SQ0001
         GIXSQL         BY VALUE 0
         GIXSQL     END-CALL. *)
      | DeclareCursorVar (_cur_name, _var_name) ->
        [ Generated_type.Todo { prefix } ]
      | DeclareCursorWhithHold (_cur_name, _query) ->
        [ Generated_type.Todo { prefix } ]
    in
    let st = Generated_type.Added { content = adding } in
    let cd = st :: !cursor_declararation in
    cursor_declararation := cd
  in

  let generate_close_cursor prefix sql_var_token =
    let fun_name = "GIXSQLCursorClose" in
    let ref_value =
      let prefix = prefix ^ "    " in
      [ Generated_type.Reference { prefix; var = "SQLCA" };
        Generated_type.Reference
          { prefix; var = "\"" ^ sql_var_token ^ "\" x\"00\"" }
      ]
    in
    Generated_type.CallStatic { prefix; fun_name; ref_value }
  in

  let generate_at prefix sql ?(at = "x\"00\"") () =
    match sql with
    | SelectInto { vars; _ } ->
      generate_select_into prefix vars ~at () (*TODO AT*)
    | Rollback (rb_work_or_tran, rb_args) ->
      generate_rollback prefix rb_work_or_tran rb_args ~at ()
    | Commit (rb_work_or_tran, b) ->
      generate_commit prefix rb_work_or_tran b ~at ()
    | DeclareCursor cur ->
      add_to_cursor_declararation prefix cur ~at ();
      []
    | Insert _
    | Savepoint _
    | StartTransaction
    | Sql _ ->
      generate_declare prefix ~at ()
    | DeclareTable _
    | Prepare _
    | ExecuteImmediate _
    | ExecuteIntoUsing _
    | Delete _
    | Update _ ->
      [ Generated_type.Todo { prefix } ]
    | _ -> failwith "Unexeped At"
  in

  let generatesql ~loc ~line esql_instuction =
    let prefix = String.sub line 0 loc.char in
    match esql_instuction with
    | Sql _
    | SelectInto _
    | StartTransaction
    | DeclareTable _
    | DeclareCursor _
    | Prepare _
    | ExecuteImmediate _
    | ExecuteIntoUsing _
    | Savepoint _
    | Rollback _
    | Commit _
    | Insert _
    | Delete _
    | Update _ ->
      generate_at prefix esql_instuction ?at:(Some "x\"00\"") ()
    | Include sqlvar ->
      (*       let prefix = String.sub line 0 loc.char in *)
      [ Generated_type.Copy { prefix; file_name = sqlvar.payload } ]
    | Connect cs -> generatesql_connect cs prefix
    | Disconnect lit ->
      [ generatesql_connect_reset ~prefix ?d_connection_id:(var_opt lit) () ]
    | DisconnectAll ->
      [ generatesql_connect_reset ~prefix
          ?d_connection_id:(Some "\"*\" & x\"00\"") ()
      ]
    | Whenever (c, k) ->
      error_treatment := generate_whenever ~prefix c k :: !error_treatment;
      []
    | Begin -> generate_declare prefix ()
    | BeginDeclare
    | EndDeclare ->
      [] (*do nothing*)
    | Close var -> [ generate_close_cursor prefix var.payload ]
    | At (at, sql) -> generate_at prefix sql ?at:(var_opt (Some at)) ()
    | Exeption _
    | Open (_, _)
    | Fetch (_, _)
    | Ignore _ ->
      (*TODO*)
      [ Generated_type.Todo { prefix } ]
  in

  let rec output lines statements =
    match statements with
    | [] ->
      List.map
        (fun (_, _, line) -> Generated_type.NoChange { content = line })
        lines
    | (begin_loc, stmt) :: statements -> begin
      match begin_loc with
      | None ->
        let res =
          List.map
            (fun (_, _, line) -> Generated_type.NoChange { content = line })
            lines
        in
        begin
          match stmt with
          | END_PROCEDURE_DIVISION ->
            res @ end_procedure_division (List.rev !cursor_declararation)
          | _ -> res
        end
      | Some begin_loc -> output_statement lines begin_loc stmt statements
    end
  and output_statement cur_lines begin_loc stmt statements =
    match cur_lines with
    | [] -> assert false
    | (filename, i, line) :: lines -> (
      if filename <> begin_loc.filename || i < begin_loc.line then begin
        Generated_type.NoChange { content = line }
        :: output_statement lines begin_loc stmt statements
      end else
        match stmt with
        | LINKAGE_SECTION { defined } ->
          if defined then begin
            Generated_type.NoChange { content = line }
            :: ([ linkage_section ] @ output lines statements)
          end else begin
            comment "> Add missing LINKAGE SECTION"
            :: Generated_type.Added
                 { content = [ Generated_type.LinkageSection ] }
            :: ([ linkage_section ] @ output cur_lines statements)
          end
        | WORKING_STORAGE { defined } ->
          if defined then begin
            Generated_type.NoChange { content = line }
            :: (working_storage_section @ output lines statements)
          end else begin
            comment "> Add missing WORKING-STORAGE SECTION"
            :: Generated_type.Added
                 { content = [ Generated_type.WorkingStorageSection ] }
            :: (working_storage_section @ output cur_lines statements)
          end
        | EXEC_SQL { end_loc; with_dot; tokens } ->
          old_statements := line :: !old_statements;
          if i = end_loc.line then begin
            let trans_stm = generatesql ~loc:begin_loc ~line tokens in
            let old_stms = List.rev !old_statements in
            let with_dot, error_treatment =
              match trans_stm with
              | [] -> false, [] (*if nothing is generated, we don't need error treatment or dots *)
              | _ -> with_dot, !error_treatment
            in
            old_statements := [];
            Generated_type.Change
              { old_stms; trans_stm; error_treatment; with_dot }
            :: output lines statements
          end else
            output_statement lines begin_loc stmt statements
        | PROCEDURE_DIVISION_DOT { end_loc } ->
          if i = end_loc.line then begin
            comment ("> REMOVED: " ^ line)
            :: (* for now, just put it back *)
               Generated_type.Added
                 { content = [ Generated_type.ProcedureDivision ] }
            :: output lines statements
          end else
            comment ("> REMOVED: " ^ line)
            :: output_statement lines begin_loc stmt statements
        | DECLARATION _ ->
          comment ("> REMOVED: " ^ line) :: output lines statements
          (*
        | IS_SQLVAR { end_loc } ->
          
             if i = begin_loc.line then begin
               let before_macro = String.sub line 0 begin_loc.char in
               Printf.bprintf ctxt.b "%s%s" before_macro
                 "SOME STRING THAT REPLACE IS SQLVAR";
               if begin_loc.line <> end_loc.line then
                 Printf.bprintf ctxt.b "\n          "
             end;
             if i = end_loc.line then (
               let len = String.length line in
               (* This code won't work with tabulations, because
                  the end_loc.char is wrong in such a case *)
               let after_macro =
                 String.sub line (end_loc.char + 1) (len - end_loc.char - 1)
               in
               Printf.bprintf ctxt.b "%s\n" after_macro;
               output lines statements
             ) else
               output_statement lines begin_loc stmt statements *)
        | BEGIN_PROCEDURE_DIVISION { enabled } ->
          ( if !enabled then
              begin_procedure_division ~loc:begin_loc
            else
              [ comment "> BEGIN PROCEDURE DIVISION disabled" ] )
          @ output cur_lines statements
        | END_PROCEDURE_DIVISION ->
          end_procedure_division (List.rev !cursor_declararation)
          @ output cur_lines statements
        | COPY { end_loc; filename; contents } ->
          let added = comment ("> INLINED:" ^ line) in
          if i = end_loc.line then begin
            let copylines = EzString.split contents '\n' in
            let copylines =
              List.mapi (fun i line -> (filename, i + 1, line)) copylines
            in
            let lines = copylines @ lines in
            added :: output lines statements
          end else
            added :: output_statement lines begin_loc stmt statements )
  in
  let result = output lines sql_statements in
  let b = Buffer.create 1000 in
  let ctxt = { b; main_filename = filename } in
  Printf.bprintf ctxt.b "%s"
    (Format.asprintf "%a" Generated_type.Printer.pp result);
  Buffer.contents b