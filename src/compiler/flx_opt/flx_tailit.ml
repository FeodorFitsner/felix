open Flx_util
open Flx_list
open Flx_ast
open Flx_types
open Flx_print
open Flx_set
open Flx_mtypes2
open Flx_typing
open Flx_mbind
open List
open Flx_unify
open Flx_treg
open Flx_generic
open Flx_maps
open Flx_exceptions
open Flx_use
open Flx_child
open Flx_call

let hfind msg h k =
  try Hashtbl.find h k
  with Not_found ->
    print_endline ("flx_inline Hashtbl.find failed " ^ msg);
    raise Not_found


let isvariable bsym_table i =
  let id,_,_,entry = Hashtbl.find bsym_table i in match entry with
  | BBDCL_var _ | BBDCL_val _ ->
  (* print_endline ("Var/Val " ^ id ^ "<" ^ si i ^">"); *) true
  | _ -> false

let isfun bsym_table i =
  let id,_,_,entry = Hashtbl.find bsym_table i in match entry with
  | BBDCL_function _ | BBDCL_procedure _ ->
  (*print_endline ("Fun/proc " ^ id ^ "<" ^ si i ^">"); *) true
  | _ -> false

let add_xclosure syms cls e =
  (*
  print_endline ("chk cls for " ^ sbe syms.sym_table bsym_table e);
  *)
  match e with
  | BEXPR_closure (i,ts),t -> cls := IntSet.add i !cls
  | _ -> ()

let ident x = x

(* WARNING!! closure here has TWO meanings: a BEXPR_closure,
  and ALSO the setwise closure of all such explicit closure
  terms ..
*)

let expr_find_xclosures syms cls e =
  iter_tbexpr ignore (add_xclosure syms cls) ignore e

let exe_find_xclosure syms cls exe =
  iter_bexe ignore (expr_find_xclosures syms cls) ignore ignore ignore exe

let exes_find_xclosure syms cls exes =
  iter (exe_find_xclosure syms cls) exes

let exes_get_xclosures syms exes =
  let cls = ref IntSet.empty in
  exes_find_xclosure syms cls exes;
  !cls

let function_find_xclosure syms cls bsym_table i =
  let _,_,_,entry = Hashtbl.find bsym_table i in
  let exes =
    match entry with
    | BBDCL_procedure (_,_,_,exes)
    | BBDCL_function (_,_,_,_,exes) -> exes
    | _ -> []
  in
  (*
  print_endline ("ROUTINE " ^ si i);
  iter (fun exe -> print_endline (string_of_bexe syms.sym_table 0 exe)) exes;
  *)
  exes_find_xclosure syms cls exes

let functions_find_xclosures syms cls bsym_table ii =
  IntSet.iter
  (function_find_xclosure syms cls bsym_table)
  ii

let rec check_ahead i n ls res : (int * int * btypecode_t) list =
  if n = 0 then rev res else match ls with
  | [] -> []
  | h :: t ->  match h with
  | BEXE_init (_,k, ( BEXPR_get_n (p,(BEXPR_name (j,[]),_)),typ))

  | BEXE_assign (_,(BEXPR_name (k,[]),_), ( BEXPR_get_n (p,(BEXPR_name (j,[]),_)),typ))
    when i = j -> check_ahead i (n-1) t ((k,p,typ)::res)

  | _ -> []

let rec drop n ls =
  if n = 0 then ls else match ls with
  | h :: t -> drop (n-1) t
  | [] -> assert false


(* This routine checks the only use of i is to get its n'th projection *)
exception BadUse
let rec check_proj_wrap_expr n i e = match e with
  | BEXPR_name (i',_),_ when i = i' -> raise BadUse
  | BEXPR_get_n (n', (BEXPR_name (i',_),_)),_
     when i = i' && n = n' ->  ()

  | x -> flat_iter_tbexpr ignore (check_proj_wrap_expr n i) ignore x

let check_proj_wrap_exe syms bsym_table n i x =
  try
    iter_bexe ignore (check_proj_wrap_expr n i) ignore ignore ignore x
  with BadUse ->
    (*
    print_endline ("Bad use of " ^ si i ^ ".(" ^ si n ^") in " ^
      string_of_bexe syms.sym_table bsym_table 0 x
    );
    *)
    raise BadUse

let check_proj_wrap_exes syms bsym_table n i xs =
  iter (check_proj_wrap_exe syms bsym_table n i) xs

let check_proj_wrap_entry syms bsym_table n i k =
  let id,_,_,entry = hfind "check_proj_wrap_entry" bsym_table k in
  match entry with
  | BBDCL_function (_,_,_,_,exes)
  | BBDCL_procedure (_,_,_,exes) ->
    (*
    print_endline ("Check use  of " ^ si i ^ ".(" ^ si n ^") in " ^ id);
    *)
    check_proj_wrap_exes syms bsym_table n i exes
  | _ -> ()

let check_proj_wrap_closure syms bsym_table descend usage n i e =
  (*
  print_endline ("Check use  of " ^ si i ^ ".(" ^ si n ^") in expr=" ^ sbe syms.sym_table bsym_table e);
  *)
  check_proj_wrap_expr n i e;
  (*
  print_endline "Now, check in dependents";
  *)
  let u = expr_uses_unrestricted syms descend usage e in
  IntSet.iter (check_proj_wrap_entry syms bsym_table n i) u

let tailit syms bsym_table child_map uses id this sr ps vs exes : bexe_t list =
  (*
  print_endline ("======= Tailing " ^ id ^ "<" ^ si this ^ "> exes=====");
  iter (fun x -> print_endline (string_of_bexe syms.sym_table 0 x)) exes;
  print_endline "======== END BODY ========";
  *)

  let ts' = map (fun (_,i) -> BTYP_var (i,BTYP_type 0)) vs in
  let pset = fold_left (fun s {pindex=i} -> IntSet.add i s) IntSet.empty ps in
  let parameters = ref [] in
  let descend = descendants child_map this in
  let children = try Hashtbl.find child_map this with Not_found -> [] in
  let can_loop () =
    let varlist = filter (isvariable bsym_table) children in
    let funset = IntSet.filter (isfun bsym_table) descend in

    (*
    print_endline ("Procedure has " ^ si (length varlist) ^ " variables");
    print_endline ("Procedure has " ^ si (IntSet.cardinal funset) ^ " child funcs");
    *)

    let cls = ref IntSet.empty in
    functions_find_xclosures syms cls bsym_table funset;
    (* THIS FUNCTION IS BEING INLINED .. WE CANNOT LOOKUP ITS EXES!! *)
    exes_find_xclosure syms cls exes;
    (*
    print_endline ("Total xclosures " ^ si (IntSet.cardinal !cls));
    *)
    let kidcls = IntSet.inter !cls funset in
    (*
    print_endline ("Kid xclosures " ^ si (IntSet.cardinal kidcls));
    *)
    try
      IntSet.iter
      (fun i ->
        let usage = Hashtbl.find uses i in
        iter
        (fun j ->
          let usesj =   mem_assoc j usage in
          (*
          if usesj then
            print_endline (si i ^ " uses var " ^ si j)
          ;
          *)
          if usesj then raise Not_found;
        )
        varlist
      )
      kidcls
      ;
      true
    with
    | Not_found -> false
  in

  let jump_done = ref false in
  let lc = !(syms.counter) in incr (syms.counter);
  let start_label = "start_" ^ si lc in

  (* note reverse order *)
  (* Weirdly, this works for BOTH tail calls
    and tail applies
  *)
  let cal_tail_call e =
    match length ps with
    | 0 ->
      [
        BEXE_goto (sr,start_label);
        BEXE_comment (sr,"tail rec call (0)")
      ]
    | 1 ->
      let {pindex=k} = hd ps in
      [
        BEXE_goto (sr,start_label);
        BEXE_init (sr,k,e);
        BEXE_comment (sr,"tail rec call (1)")
      ]
    | _ ->
      begin match e with
      | BEXPR_tuple ls,_ ->
        (*
        print_endline ("TUPLE ASSGN " ^ sbe syms.sym_table bsym_table e);
        *)
        assert (length ls = length ps);
        let pinits =
          map2
          (fun {pid=name; pindex=i; ptyp=t} e ->
            i,(name,t,e,expr_uses syms descend uses pset e)
          )
          ps ls
        in
        let tmps,exes = Flx_passign.passign syms bsym_table pinits ts' sr in
        parameters := tmps @ !parameters;
        let result = ref exes in
        result :=  BEXE_goto (sr,start_label) :: !result;
        (*
          print_endline "Tail opt code is:";
          iter (fun x -> print_endline (string_of_bexe syms.sym_table 0 x) ) (rev !result);
        *)
        !result

      | _ ->
        print_endline "NON TUPLE TAIL CALL";
        let t = snd e in
        let pix =
          try assoc t !parameters
          with Not_found ->
            let pix = !(syms.counter) in incr syms.counter;
            parameters := (t,pix) :: !parameters;
            pix
        in
        let p = BEXPR_name (pix,ts'),t in
        let n = ref 0 in
        let param_decode =
          map
          (fun {pindex=ix; ptyp=prjt} ->
            let prj = reduce_tbexpr bsym_table (BEXPR_get_n (!n,p),prjt) in
            incr n;
            BEXE_init (sr,ix,prj)
          )
          ps
        in
        [
          BEXE_goto (sr,start_label);
        ]
        @
        param_decode
        @
        [
          BEXE_init (sr,pix,e);
          BEXE_comment (sr,"tail rec call (2)")
        ]
      end
  in
  let cal_asgn1 pas ls =
    let n = length pas in
    (* vset is the restriction set applied to the usage closure to
      restrict attention to the LHS variables
    *)
    let vset = fold_left (fun acc (k,_,_) ->IntSet.add k acc) IntSet.empty pas in
    let asgns = map
      (fun (k,p,t) ->
        let name = "DUNNO_" ^ si k in
        let e = nth ls p in
        let d = expr_uses syms descend uses vset e in
        k, (name,t,e,d)
      )
      pas
    in
      let tmps,exes = Flx_passign.passign syms bsym_table asgns ts' sr in
      parameters := tmps @ !parameters;
      if syms.compiler_options.print_flag then begin
        print_endline "CALCULATED ACTUAL PARALLEL ASSIGNMENTS!";
        iter (fun x ->
          print_endline (string_of_bexe syms.sym_table bsym_table 0 x)
        )
        (rev exes)
        ;
      end;
      (* NOTE: we have to KEEP the tuple variable in case
        it is used elsewhere .. it should get dropped by later
        garbage collection if it isn't used!
      *)
    exes
  in
  let asgn2 i t ls =
    map2
    (fun (e,t' as x) j ->
      BEXE_assign
      (
        sr,
        (BEXPR_get_n (j,(BEXPR_name (i,ts'),t)),t'),
        x
      )
    )
    ls
    (nlist (length ls))
  in
  let rec aux inp res =
    let cal_par i t ls h tail =
      if syms.compiler_options.print_flag then
      begin
        print_endline ("flx_tailit found possible parallel assignment opportunity in:");
        print_endline (string_of_bexe syms.sym_table bsym_table 0 h);
      end;

      (* the descendants of the variables parents! *)
      let parent =
        match hfind "parallel assign" bsym_table i with
        | _,parent,_,_ -> parent
      in
      let descend = match parent with
        | Some parent -> descendants child_map parent
        | None ->
          let d = ref IntSet.empty in
          Hashtbl.iter (fun i _ -> d := IntSet.add i !d) child_map;
          !d
      in

      let n = length ls in
      let pas = check_ahead i n tail [] in

      (* SPECIAL CASE

        tmp = r1, r2, r3;
        l1 = tmp.(0);
        l2 = tmp.(1);
        l3 = tmp.(2);

        generated by desugaring routine

      *)
      if length pas = n then begin
        if syms.compiler_options.print_flag then
        print_endline "FULLY OPTIMISE";
        if syms.compiler_options.print_flag then begin
          let rec p n ls = if n > 0 then match ls with
            | h :: t ->
               print_endline (string_of_bexe syms.sym_table bsym_table 0 h);
               p (n-1) t
            | [] -> assert false
          in
          p n tail;
          print_endline "Assigns are:";
          let rec pr xs = match xs with
          | (k,p,t) :: tl ->
             print_endline (
               "var " ^ si k ^ " : " ^sbt syms.sym_table t^
               " = var " ^ si i^ ".(" ^ si p ^") = " ^
               sbe syms.sym_table bsym_table (nth ls p)
             );
             pr tl
          | [] -> ()
          in
          pr pas;
        end;

        let exes = cal_asgn1 pas ls in
        aux (drop n tail) (exes @ h :: res)
      end
      else  (* length pas <> n *)
      begin
        let can_opt =
          try
            let counter = ref 0 in
            iter (fun e ->
              let n = !counter in incr counter;
              check_proj_wrap_closure syms bsym_table descend uses n i e
            )
            ls;
            true
          with
            BadUse -> false
        in
        if can_opt then
        begin
          if syms.compiler_options.print_flag then
          begin
            print_endline ("SEMI OPTIMISE!");
          end;
          let exes = asgn2 i t ls in
          (* the 'rev' here is not necessary, but it preserves the
             order of writing by the user, i.e. from lowest index
             to highest index
          *)
          aux tail (rev exes @ res)
        end
        else begin
          (*
          assert (d = IntSet.singleton i);
          *)
          if syms.compiler_options.print_flag then
            print_endline ("UNOPTIMISED");
          aux tail (h::res)
        end
      end
    in
    match inp with
    | (BEXE_call_direct (sr,i,ts,a)) as x :: tail  -> assert false

    | (BEXE_call (sr,(BEXPR_closure(i,ts),_),a)) as x :: tail
      when (i,ts)=(this,ts') && Flx_cflow.tailable exes [] tail
      ->
      if can_loop ()
      then begin
        (*
        print_endline ("--> Tail rec call optimised " ^ si this);
        *)
        jump_done := true;
        let res = cal_tail_call a @ res
        in aux tail res
      end else begin
        (*
        print_endline ("--> Tail rec call NOT optimised " ^ si this);
        *)
        aux tail (x::res)
      end

    | BEXE_fun_return (sr,(BEXPR_apply_direct(i,ts,a),_)) :: tail -> assert false

    | BEXE_fun_return (sr,(BEXPR_apply((BEXPR_closure (i,ts),_),a),_)) :: tail
      when (i,ts)=(this,ts')
      ->
       (*
       print_endline ("--> Tail rec apply " ^ si this);
       *)
       jump_done := true;
       let res = cal_tail_call a @ res
       in aux tail res

    | BEXE_fun_return (sr,(BEXPR_apply((BEXPR_closure (i,ts),_),a),_)) as x :: tail
      ->
      (*
      print_endline ("--> NONSELF? Tail rec apply " ^ si i);
      print_endline ("This = " ^ si this);
      *)
      aux tail (x::res)


    | (BEXE_call(sr,(BEXPR_closure (i,ts),_),a)) as x :: tail  ->
      (*
      print_endline ("Untailed call " ^ si i ^ "["^catmap "," (sbt syms.sym_table) ts^"]");
      print_endline ("This = " ^ si this);
      print_endline ("ts'=" ^"["^catmap "," (sbt syms.sym_table) ts'^"]");
      print_endline "TAIL=";
      iter (fun x -> print_endline (string_of_bexe syms.sym_table 0 x)) tail;
      print_endline "-- end of tail --";
      *)
      aux tail (x::res)

    | [] -> rev res (* forward order *)
    | BEXE_init (sr,i,(BEXPR_tuple ls,t)) as h :: tail
      ->
        cal_par i t ls h tail

    | (BEXE_assign (sr,(BEXPR_name (i,[]),_),(BEXPR_tuple ls,t)) as h) :: tail
      ->
       cal_par i t ls h tail

    | (BEXE_assign (sr,x,(BEXPR_tuple ls,t)) as h) :: tail
      ->
      let rec unproj e = match map_tbexpr ident unproj ident e with
      | BEXPR_get_n (k,(BEXPR_tuple ls,_)),_ -> nth ls k
      | x -> x
      in
      let ls = map unproj ls in
      (*
      print_endline "DETECTED PARALLEL ASSIGN WITH LHS EXPR";
      print_endline (string_of_bexe syms.sym_table bsym_table 0 h);
      *)
      let i = !(syms.counter) in incr (syms.counter);
      let n = length ls in
      let pbase = !(syms.counter) in syms.counter := !(syms.counter) + n;
      let me e = match expr_maybe_matches syms.counter syms.sym_table [] [] x e with
        | Some ([],[]) -> true
        | None -> false
        | _ -> assert false
      in
      let rec repl e = match map_tbexpr ident repl ident e with
        | x when me x -> BEXPR_name (i,[]),t
        | BEXPR_get_n (k,(BEXPR_name (j,[]),t)),t' when i = j->
          BEXPR_name (pbase+k,[]),t'
        | x -> x
      in
      let check = me x in
      (*
      print_endline (if check then "MATCHES SELF" else "DOES'T MATCH SELF");
      *)
      if check then begin
        let ls' = map repl ls in
        (*
        let j = ref 0 in
        iter2 (fun x x' ->
          print_endline ("Recoded " ^
            sbe syms.sym_table bsym_table x ^
            "\nas var " ^ si (!j+pbase) ^ "=" ^
            sbe syms.sym_table bsym_table x' ^
            "\n"
          );
          incr j
        )
        ls ls'
        ;
        *)
        let vset = fold_left (fun acc k ->IntSet.add (k+pbase) acc) IntSet.empty (nlist n) in
        let asgns = map
          (fun k ->
          let name = "DUNNO_" ^ si (k+pbase) in
          let e = nth ls' k in
          let _,t = e in
          let d = expr_uses syms descend uses vset e in
          (*
          print_endline ("var " ^ si (k+pbase) ^ " = " ^
            sbe syms.sym_table bsym_table e ^ " USES " ^ string_of_intset d);
          *)
          k+pbase, (name,t,e,d)
        )
        (nlist n)
        in
        let tmps,exes = Flx_passign.passign syms bsym_table asgns ts' sr in
        parameters := tmps @ !parameters;
        if syms.compiler_options.print_flag then
        begin
          print_endline "PARALLEL ASSIGNMENTS (before unsub) =";
          iter (fun x ->
            print_endline (string_of_bexe syms.sym_table bsym_table 0 x)
          )
          (rev exes)
          ;
        end;
        let rec undo_expr e = match map_tbexpr ident undo_expr ident e with
        | BEXPR_name (j,[]),t when i = j  -> x
        | BEXPR_name (j,[]),t when j >= pbase && j < pbase + n-> BEXPR_get_n (j-pbase,x),t
        | x -> x
        in
        let undo_st st = match st with
        | BEXE_init (sr,j,e) when j >= pbase && j < pbase + n ->
          let k = j - pbase in
          let _,t' = nth ls k in
          BEXE_assign (sr,(BEXPR_get_n (k,x),t'),undo_expr e)

        | x -> map_bexe ident undo_expr ident ident ident x
        in
        let exes = map undo_st exes in
        if syms.compiler_options.print_flag then
        begin
          print_endline "PARALLEL ASSIGNMENTS (after unsub) = ";
          iter (fun x ->
            print_endline (string_of_bexe syms.sym_table bsym_table 0 x)
          )
          (rev exes)
          ;
        end;
        aux tail (exes @ res)
      end
      else
      aux tail (h::res)


    | h :: t  -> aux t (h::res)
    in
      let exes = aux exes [] in

      (* instantiate any parameter temporaries *)
      iter
        (fun (paramtype, parameter) ->
          let entry = BBDCL_tmp (vs,paramtype) in
          let kids =
            try Hashtbl.find child_map this
            with Not_found -> []
          in
          Hashtbl.replace child_map this (parameter::kids);
          let id = "_trp_" ^ si  parameter in
          Hashtbl.add bsym_table parameter (id,Some this,sr,entry);
        )
      !parameters
      ;
      (* return with posssible label at start *)
      let exes =
        if !jump_done
        then BEXE_label (sr,start_label) :: exes
        else exes
      in
        (*
        print_endline ("Tailed exes = ");
        iter (fun exe -> print_endline (string_of_bexe syms.sym_table 0 exe)) exes;
        *)
        exes