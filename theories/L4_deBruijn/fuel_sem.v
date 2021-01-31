Require Import Coq.Arith.Arith Coq.NArith.BinNat omega.Omega Coq.Strings.String
        Coq.Lists.List Structures.OrdersEx Lia.
Require Import Common.Common.
Require Import L4.expression.
Require Import L6.algebra L6.tactics.

Open Scope alg_scope.

(* Environment semantics values *)
Inductive value :=
| Con_v : dcon -> list value -> value 
| Prf_v : value
| Clos_v : list value -> name -> expression.exp -> value
| ClosFix_v : list value -> efnlst -> N -> value.

Lemma value_ind' (P : value -> Prop) :
  (forall dcon vs, Forall P vs -> P (Con_v dcon vs)) ->
  (P Prf_v) ->
  (forall vs na e, Forall P vs -> P (Clos_v vs na e)) ->
  (forall vs fnl n, Forall P vs -> P (ClosFix_v vs fnl n)) ->
  (forall v,  P v).
Proof.
  intros H1 H2 H3 H4.
  fix IHv 1; intros v. destruct v.
  - eapply H1. induction l.
    constructor.
    constructor. eapply IHv. eassumption.
  - eauto.
  - eapply H3. induction l.
    constructor.
    constructor. eapply IHv. eassumption. 
  - eapply H4. induction l.
    constructor.
    constructor. eapply IHv. eassumption. 
Qed.

(* Definition of env *)
Definition env := list value.

Inductive result :=
| Val : value -> result
| OOT : result.


Section L4_fuel.

  Definition exp_to_fin (e: exp) : fin :=
    match e with
    | Var_e _
    | Lam_e _ _
    | Fix_e _ _
    | Prf_e
    | Con_e _ _ => One (* Values map to One *)
                     
    | App_e _ _ 
    | Match_e _ _ _ 
    | Let_e _ _ _ 
    | Prim_e _ => Two (* Reducible terms to Two *)
    end.
      
  
  Class L4_resource {A} :=
  { HRes :> @resource fin A;
    one := (fun e => @one_i _ _ HRes (exp_to_fin e));
    one_ctx := (fun C => @one_i _ _ HRes (exp_ctx_to_fin C)) }.

  (* Fuel resource *)

  Class L4_fuel_resource {A} :=
    { HRexp_f :> @L4_resource A;
      HOrd    :> @ordered fin A HRes;
      HOne    :> @resource_ones fin A HRes;
      HNat    :> @nat_hom fin A HRes
    }.

End L4_fuel.

Section Util.

  (** Helper functions for going between exps and lists *)
  Fixpoint exps_to_list (es : expression.exps) : list exp :=
    match es with
    | enil => nil
    | econs e es' =>
      let l := exps_to_list es' in
      e::l
    end.

  Definition make_rec_env_rev_order (fnlst : efnlst) (rho : env) : env :=
    let fix make_env_aux l :=
        match l with
        | nil => rho
        | cons n l' =>
          let env' := make_env_aux l' in
          ((ClosFix_v rho fnlst (N.of_nat n)) :: env')
        end
    in
    make_env_aux (list_to_zero (efnlength fnlst)).

  Lemma enthopt_inlist_Forall (P : exp -> Prop) :
    forall efnl n e,
      Forall (fun (p : name * exp) => let (_, e) := p in P e) (efnlst_as_list efnl) ->
      enthopt (N.to_nat n) efnl = Some e ->
      P e.
  Proof.
    intros efnl n.
    generalize (N.to_nat n). induction efnl; intros n' e' Hall Hnth.
    - destruct n'; simpl in Hnth; inv Hnth.
    - destruct  n'. inv Hnth.
      + inv Hall. eassumption.
      + inv Hall. simpl in Hnth. eapply IHefnl.
        eassumption. eassumption.
  Qed.
  
  Lemma make_rec_env_rev_order_app fns vs :
    exists vs', make_rec_env_rev_order fns vs = vs' ++ vs /\
                List.length vs' = efnlength fns /\
                forall n, (n < efnlength fns)%nat ->
                          nth_error vs' n = Some (ClosFix_v vs fns (N.of_nat (efnlength fns - n - 1))).
  Proof.
    unfold make_rec_env_rev_order. generalize (efnlength fns) as m. 
    induction m.
    - simpl. eexists []. split. reflexivity. split.
      compute. reflexivity.
      intros. lia.
    - destructAll.
      eexists (ClosFix_v vs fns (N.of_nat (Datatypes.length x)) :: x). simpl.
      split; [ | split ].
      + rewrite H. reflexivity.
      + reflexivity.
      + intros. destruct n.
        * simpl. rewrite Nat.sub_0_r. reflexivity.
        * simpl. eapply H1. lia.
  Qed.
  
End Util. 

Section FUEL_SEM.

  Inductive Forall3 {A B C : Type} (R : A -> B -> C -> Prop) : list A -> list B -> list C -> Prop :=
    Forall3_nil : Forall3 R [] [] []
  | Forall3_cons :
      forall (x : A) (y : B) (z : C) (l : list A) (l' : list B) (l'' : list C),
        R x y z -> Forall3 R l l' l'' -> Forall3 R (x :: l) (y :: l') (z :: l'').

  Context {fuel : Type} {Hf : @L4_fuel_resource fuel}.

  Fixpoint add_list (l : list fuel) : fuel :=
    match l with
    | nil => <0>
    | cons f fs => f <+> add_list fs
    end.
  
  
  (** * {Fuel,environment}-based semantics for L4 *)
  Inductive eval_env_step: env -> exp -> result -> fuel -> Prop :=
  | eval_Con_step:
      forall (es : expression.exps) (vs : list value) (rho: env) (dc: dcon) (fs : fuel),
        eval_fuel_many rho es vs fs ->
        eval_env_step rho (Con_e dc es) (Val (Con_v dc vs)) fs
  | eval_Con_step_OOT:
      forall (es es1 es2: expression.exps) (e : exp) (vs : list value) (rho: env) (dc: dcon) (fs f : fuel),
        exps_to_list es = exps_to_list es1 ++ e :: exps_to_list es2 ->
        eval_fuel_many rho es1 vs fs ->
        eval_env_fuel rho e OOT f ->
        eval_env_step rho (Con_e dc es) OOT (fs <+> f)

  | eval_App_step:
      forall (e1 e2 e1': expression.exp) v2 r (na : name) (rho rho': env)
             (f1 f2 f3 : fuel),
        eval_env_fuel rho e1 (Val (Clos_v rho' na e1')) f1 ->
        eval_env_fuel rho e2 (Val v2) f2 ->
        eval_env_fuel (v2::rho') e1' r f3 ->
        eval_env_step rho (App_e e1 e2) r (f1 <+> f2 <+> f3)
  | eval_App_step_OOT1 :
      forall (e1 e2 : expression.exp) (rho : env) (f1 : fuel),
        eval_env_fuel rho e1 OOT f1 ->
        eval_env_step rho (App_e e1 e2) OOT f1
  | eval_App_step_OOT2 :
      forall (e1 e2 : expression.exp) (v : value) (rho : env) (f1 f2 : fuel),
        eval_env_fuel rho e1 (Val v) f1 ->
        eval_env_fuel rho e2 OOT f2 ->
        eval_env_step rho (App_e e1 e2) OOT (f1 <+> f2)

                      
  | eval_Let_step:
      forall (e1 e2 : expression.exp) (v1 : value) (r : result) (rho: env) (na: name) (f1 f2 : fuel),
        eval_env_fuel rho e1 (Val v1) f1 ->
        eval_env_fuel (v1::rho) e2 r f2 ->
        eval_env_step rho (Let_e na e1 e2) r (f1 <+> f2)
  | eval_Let_step_OOT:
      forall (e1 e2 : expression.exp) (rho: env) (na: name) (f1 : fuel),
        eval_env_fuel rho e1 OOT f1 ->
        eval_env_step rho (Let_e na e1 e2) OOT f1
                      
  | eval_FixApp_step: 
      forall (e1 e2 e': expression.exp) (rho rho' rho'': env) (n: N) (na : name)
             (fnlst: efnlst) (v2 : value) r f1 f2 f3,
        eval_env_fuel rho e1 (Val (ClosFix_v rho' fnlst n)) f1 ->
        enthopt (N.to_nat n) fnlst = Some (Lam_e na e') ->
        make_rec_env_rev_order fnlst rho' = rho'' ->
        eval_env_fuel rho e2 (Val v2) f2 ->
        eval_env_fuel (v2 :: rho'') e' r f3 ->
        eval_env_step rho (App_e e1 e2) r (f1 <+> f2 <+> f3)
  | eval_FixApp_step_OOT1:
      forall (e1 e2 : expression.exp) (rho : env) (f1 : fuel),
        eval_env_fuel rho e1 OOT f1 ->
        eval_env_step rho (App_e e1 e2) OOT f1
  | eval_FixApp_step_OOT2: 
      forall (e1 e2 : expression.exp) (v : value) (rho : env) f1 f2,
        eval_env_fuel rho e1 (Val v) f1 ->
        eval_env_fuel rho e2 OOT f2 ->
        eval_env_step rho (App_e e1 e2) OOT (f1 <+> f2)
                      
  | eval_Match_step:
      forall (e1 e': expression.exp) (rho: env) (dc: dcon) (vs: list value)
             (n: N) (brnchs: branches_e) (r: result) f1 f2,
        eval_env_fuel rho e1 (Val (Con_v dc vs)) f1 ->
        find_branch dc (N.of_nat (List.length vs)) brnchs = Some e' ->
        eval_env_fuel ((List.rev vs) ++ rho) e' r f2 ->
        eval_env_step rho (Match_e e1 n brnchs) r (f1 <+> f2)
  | eval_Match_step_OOT:
      forall (e1 : expression.exp) (rho: env) (n: N) (br: branches_e) (f1 : fuel),
        eval_env_fuel rho e1 OOT f1 ->
        eval_env_step rho (Match_e e1 n br) OOT f1

  with eval_fuel_many: env -> exps -> list value -> fuel -> Prop :=
  | eval_many_enil :
      forall rho,
        eval_fuel_many rho enil [] <0>
  | eval_many_econs :
      forall rho e es v vs f fs,
        eval_env_fuel rho e (Val v) f ->
        eval_fuel_many rho es vs fs ->
        eval_fuel_many rho (econs e es) (v :: vs) (f <+> f)
                      
  with eval_env_fuel: env -> exp -> result -> fuel -> Prop :=
  (* Values *) 
  | eval_Var_fuel:
      forall (x: N) (rho: env) (v: value),
        nth_error rho (N.to_nat x) = Some v ->
        eval_env_fuel rho (Var_e x) (Val v) <0>
  | eval_Lam_fuel:
      forall (e: expression.exp) (rho:env) (na: name),
        eval_env_fuel rho (Lam_e na e) (Val (Clos_v rho na e)) <0>
  | eval_Fix_fuel:
      forall (n: N) (rho: env) (fnlst: efnlst),
        eval_env_fuel rho (Fix_e fnlst n) (Val (ClosFix_v rho fnlst n)) <0>
  (* OOT *)
  | eval_OOT :
      forall rho (e : exp) (c : fuel),
        (c << one e) ->
        eval_env_fuel rho e OOT c
  (* STEP *)
  | eval_step : (* take a step *)
      forall rho e r (c : fuel),
        eval_env_step rho e r c ->
        eval_env_fuel rho e r (c <+> (one e)).


  Scheme eval_env_step_ind' := Minimality for eval_env_step Sort Prop
    with eval_fuel_many_ind' :=  Minimality for eval_fuel_many Sort Prop
    with eval_env_fuel_ind' := Minimality for eval_env_fuel Sort Prop.


  Section WF. 
  
    Definition well_formed_in_env (e : exp) (rho : list value) :=
      exp_wf (N.of_nat (length rho)) e.

    
    Inductive well_formed_val : value -> Prop :=
    | Wf_Con :
        forall dc vs,
          Forall well_formed_val vs ->
          well_formed_val (Con_v dc vs)
    | Wf_Prf :
        well_formed_val Prf_v
    | Wf_Clos :
        forall vs n e,
          Forall well_formed_val vs -> 
          (forall x, well_formed_in_env e (x :: vs)) ->
          well_formed_val (Clos_v vs n e)
    | Wf_ClosFix :
        forall vs n efns,
          Forall well_formed_val vs ->
          n < efnlst_length efns ->
          Forall (fun (p : name * exp) =>
                    let (n, e) := p in
                    isLambda e /\
                    exp_wf (efnlst_length efns + (N.of_nat (length vs))) e) (efnlst_as_list efns) ->
          well_formed_val (ClosFix_v vs efns n).

    

    Definition well_formed_exps_in_env (es : exps) (rho : list value) :=
      exps_wf (N.of_nat (length rho)) es.
    
    Definition well_formed_env (rho : list value) : Prop :=
      Forall well_formed_val rho.

    Require Import Lia. 

    Lemma well_formed_in_env_Match_branches:
      forall e e' bs rho i dc vs f,
        eval_env_fuel rho e (Val (Con_v dc vs)) f ->
        well_formed_in_env (Match_e e i bs) rho ->
        find_branch dc (N.of_nat (Datatypes.length vs)) bs = Some e' ->
        well_formed_in_env e' (rev vs ++ rho).
    Proof.
      intros e e' bs rho i d vs f Heval Hwf H.
      inv Hwf.
      unfold well_formed_in_env.
      rewrite app_length. rewrite Nnat.Nat2N.inj_add.
      rewrite rev_length. eapply find_branch_preserves_wf; eassumption.
    Qed.

    Lemma well_formed_envmake_rec_env_rev_order fnlst rho rho' : 
      make_rec_env_rev_order fnlst rho = rho' ->
      well_formed_env rho ->
      Forall
        (fun p : name * exp =>
           let (_, e) := p in
           isLambda e /\
           exp_wf (efnlst_length fnlst + N.of_nat (Datatypes.length rho)) e)
        (efnlst_as_list fnlst) ->
      well_formed_env rho'.
    Proof.
      unfold make_rec_env_rev_order.
      assert (Hlen : N.of_nat (efnlength fnlst) <= efnlst_length fnlst).
      { rewrite efnlength_efnlst_length. lia. } 
      revert Hlen. generalize fnlst at 2 3 5 6. revert rho rho'.
      induction fnlst; intros rho rho' fnlst' Hlen Heq Henv Hall; eauto.
      - simpl in *. subst; eauto.
      - simpl in *. subst. 
        constructor; eauto.
        constructor; eauto.

        lia.

        eapply IHfnlst; eauto. lia.
    Qed.
           

    Lemma efnlst_wf_isLambda :
      forall n es e,
        efnlst_wf n es -> In e (efnlst_as_list es) ->
        isLambda (snd e) /\ exp_wf n (snd e).
    Proof.
      intros n es e H1 H2.
      induction es.
      - inv H2.
      - inv H1. inv H2.
        split; eassumption.
        eapply IHes; try eassumption.
    Qed.

    
    Lemma eval_env_step_preserves_wf :
      forall vs e r f,
        eval_env_fuel vs e r f ->
        forall v, r = Val v ->
                  well_formed_env vs ->
                  well_formed_in_env e vs ->
                  well_formed_val v.
    Proof.
      pose (P := fun (vs : env) (e : exp) (r : result) (f : fuel) => 
                   forall v,
                     r = Val v ->
                     well_formed_env vs ->
                     well_formed_in_env e vs ->
                     well_formed_val v).

      pose (P1 := fun (vs : env) (es : exps) (vs' : list value) (f : fuel) => 
                    well_formed_env vs ->
                    well_formed_exps_in_env es vs ->
                    Forall well_formed_val vs').

      pose (P2 := fun (vs : env) (e : exp) (r : result) (f : fuel) => 
                    forall v,
                      r = Val v ->
                      well_formed_env vs ->
                      well_formed_in_env e vs ->
                      well_formed_val v).

      intros vs e r f Heval. 
      eapply eval_env_fuel_ind' with (P := P) (P0 := P1) (P1 := P2);
      unfold P, P1, P2; intros; try congruence.
      
      - inv H1. constructor. inv H3. eapply H0; eauto.

      - subst. inv H7.
        specialize (H0 _ ltac:(reflexivity) H6 H10).
        inv H0. eapply H4; eauto.
        constructor; eauto.

      - subst. inv H5.
        eapply H2; eauto. constructor; eauto.
        unfold well_formed_in_env.
        simpl List.length.
        replace (N.of_nat (S (Datatypes.length rho))) with (1 + N.of_nat (Datatypes.length rho)) by lia.
        eassumption.

      - subst. inv H9.
        specialize (H0 _ ltac:(reflexivity) H8 H11). inv H0.
        
        eapply H6; eauto. constructor; eauto.
        now eapply well_formed_envmake_rec_env_rev_order; eauto.
        
        eapply enthopt_inlist_Forall in H14; eauto.
        inv H14. inv H2.

        unfold well_formed_in_env. simpl List.length.
        replace (N.of_nat (S (Datatypes.length (make_rec_env_rev_order fnlst rho'))))
          with (1 + N.of_nat (Datatypes.length (make_rec_env_rev_order fnlst rho'))) by lia.

        edestruct make_rec_env_rev_order_app. destructAll. rewrite H2.
        rewrite app_length. rewrite Nnat.Nat2N.inj_add.
        rewrite H7. rewrite efnlength_efnlst_length. eassumption. 

      - subst. 
        inv H6. specialize (H0 _ ltac:(reflexivity) H5 H9). inv H0.
        eapply H3; eauto.
        eapply Forall_app. split; eauto.
        eapply Forall_rev; eauto.
        eapply well_formed_in_env_Match_branches; eauto.
        constructor; eauto.

      - now constructor.

      - inv H4. constructor; eauto.

      - inv H2. inv H0; eauto.
        eapply Forall_forall in H1. eassumption.
        eapply nth_error_In. eassumption.

      - inv H1. inv H. constructor; eauto.
        intros x. unfold well_formed_in_env.
        simpl List.length.
        replace (N.of_nat (S (Datatypes.length rho))) with (1 + N.of_nat (Datatypes.length rho)) by lia.
        eassumption.

      - inv H. inv H1.
        constructor; eauto.

        eapply Forall_forall. intros. destruct x. 
        eapply efnlst_wf_isLambda in H. 
        eassumption. eassumption.

      - subst; eauto.

      - eassumption.

        Grab Existential Variables. eassumption.
    Qed. 


  End WF.
    
End FUEL_SEM.
