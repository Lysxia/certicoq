
Require Import Coq.NArith.BinNat Coq.Relations.Relations Coq.MSets.MSets Coq.MSets.MSetRBT
        Coq.Lists.List Coq.omega.Omega Coq.Sets.Ensembles.
Require Import L6.cps L6.eval L6.cps_util L6.identifiers L6.ctx L6.set_util
        L6.Ensembles_util L6.List_util L6.tactics L6.relations L6.algebra. 
Require Export L6.logical_relations L6.logical_relations_cc L6.alpha_conv L6.inline_letapp.
Require Import compcert.lib.Coqlib.

Import ListNotations.

Close Scope Z_scope.

Context (fuel trace : Type).

Definition PostT := @PostT fuel trace.
Definition PostGT := @PostGT fuel trace.

Section Compose.

  Context {A : Type}.
  
  (* Properties that the intermediate post conditions have *)
  Definition post_property := PostT -> PostGT -> Prop.
  
  Context (wf_pres : A -> A -> Prop)
          (wf : A -> Prop)
          (post_prop : post_property).
  
  
  Definition rel := PostT -> PostGT -> A -> A -> Prop.  

  Inductive R_n (R : PostT -> PostGT -> A -> A -> Prop) : nat -> A -> A -> Prop :=
  | One :
      forall (P1 P2 : PostT) (c1 : A) (c2: A),
        R P1 P2 c1 c2 ->
        wf_pres c1 c2 ->
        post_prop P1 P2 ->
        R_n R 1%nat c1 c2
  | More :
      forall (n : nat) (c1 : A) (c2: A) P1 P2 c',
        R P1 P2 c1 c' ->
        R_n R n c' c2 ->
        wf_pres c1 c' -> (* well-formedness is preserved *)
        post_prop P1 P2 ->  (* the indermediate post has some desired property *)
        R_n R (S n) c1 c2.

  
  Definition compose_rel (R1 R2 : A -> A -> Prop) (c1 : A) (c2: A) : Prop :=    
    exists c',
        R1 c1 c' /\
        R2 c' c2.
  
End Compose.

Definition pr_trivial : post_property := fun _ _  => True.

Definition wf_trivial {A} : A -> A -> Prop := fun _ _ => True.

Definition preserves_fv (e1 e2 : exp) := occurs_free e2 \subset occurs_free e1.


Section RelComp.

  Context (cenv : ctor_env) (ctag : ctor_tag).

  Context (wf_pres : exp -> exp -> Prop) (post_prop : post_property).

  Context {Hf : @fuel_resource fuel} {Ht : @trace_resource trace}.
    
  
  Definition preord_exp_n n := R_n wf_pres post_prop
                                   (fun P PG e1 e2 =>
                                      forall k rho1 rho2,
                                        preord_env_P cenv PG (occurs_free e1) k rho1 rho2 ->
                                        preord_exp cenv P PG k (e1, rho1) (e2, rho2)) n.  

  Definition preord_env_n n S := R_n wf_trivial pr_trivial (fun P PG c1 c2 => forall k, preord_env_P cenv P S k c1 c2) n.  

  Definition preord_val_n n := R_n wf_trivial pr_trivial (fun P PG c1 c2 => forall k, preord_val cenv PG k c1 c2) n.

  Definition preord_res_n n := R_n wf_trivial pr_trivial (fun P PG c1 c2 => forall k, preord_res (preord_val cenv) PG k c1 c2) n.

  Definition R_true : PostT := fun _ _ => True. 
  
  Lemma R_true_idempotent :
    same_relation _ (compose R_true R_true) R_true.
  Proof.
    firstorder.
  Qed.
  
  Lemma preord_res_n_OOT_r n v :
    ~ preord_res_n n (Res v) OOT.
  Proof.
    revert v. induction n; intros m H.
    - inv H.
    - inv H. now specialize (H1 0); eauto.
      destruct c'. specialize (H1 0). contradiction.
      eapply IHn. eassumption.
  Qed.
  
  Lemma preord_res_n_OOT_l n v :
    ~ preord_res_n n OOT (Res v).
  Proof.
    revert v. induction n; intros m H.
    - inv H.
    - inv H. specialize (H1 0). contradiction.
      destruct c'. eapply IHn. eassumption.
      now specialize (H1 0); eauto.      
  Qed.

  Context (Hwf : forall e1 e2, wf_pres e1 e2 -> preserves_fv e1 e2).


  Lemma closed_preserved e1 e2 :
    closed_exp e1 ->
    wf_pres e1 e2 ->
    closed_exp e2.
  Proof.
    intros Hc1 Hwf1. split; [| now sets ]. eapply Included_trans.
    eapply Hwf. eassumption. eapply Hc1.
  Qed.
  
  Context (Hwf_c : forall e1 e2, wf_pres e1 e2 -> closed_exp e1 -> closed_exp e2).


  Definition Pr_implies_post_upper_bound (Pr : PostT -> PostGT -> Prop) :=
    forall P PG, Pr P PG -> @post_upper_bound fuel _ trace P.  
  
  (* Adequacy, termination *)
  
  Lemma preord_exp_n_impl (n : nat) (e1 : exp) (e2: exp) :
    closed_exp e1 ->
    preord_exp_n n e1 e2 ->
    
    (forall rho1 rho2,        
      forall (v1 : res) cin cout,
        bstep_fuel cenv rho1 e1 cin v1 cout ->
        exists (v2 : res) cin' cout',
          bstep_fuel cenv rho2 e2 cin' v2 cout' /\
          preord_res_n n v1 v2).
  Proof.
    intros Hwfe Hrel. induction Hrel.
    + (* base case *)
      intros. edestruct (H (to_nat cin)); eauto.
      eapply preord_env_P_antimon; [| eapply Hwfe ]. now intros z Hin; inv Hin.  
      destructAll.
      do 3 eexists. split; eauto. eapply One. intros k.
      edestruct (H (k + to_nat cin) rho1 rho2); [| | eassumption | ].
      eapply preord_env_P_antimon; [| eapply Hwfe ].
      now intros z Hin; inv Hin. omega. destructAll.
      destruct v1.
      * destruct x; eauto.
      * destruct x; eauto. destruct x2. contradiction.
        eapply bstep_fuel_deterministic in H3; [| clear H3; eassumption ].
        inv H3. eapply preord_res_monotonic. eassumption. omega.
      * clear. firstorder.
      * clear; now firstorder.
    + intros. edestruct H; eauto. 
      eapply preord_env_P_antimon with (rho2 := rho2); [| eapply Hwfe ]. now intros z Hin; inv Hin. destructAll.
      edestruct IHHrel. eapply Hwf_c. eassumption. eassumption. eassumption.
      destructAll. 
      do 3 eexists. split; eauto.
      eapply More; [| eassumption | | eapply R_true_idempotent ].
      destruct v1.
      * destruct x; eauto.
      * destruct x; eauto. destruct x2. eapply preord_res_n_OOT_r in H7. contradiction.
        intros k.
        edestruct (H (k + to_nat cin)); [| | eassumption | ].
        eapply preord_env_P_antimon; [| eapply Hwfe ]. now intros z Hin; inv Hin. omega. destructAll.
        destruct x; eauto. simpl in H10. contradiction.
        eapply bstep_fuel_deterministic in H3; [| clear H3; eassumption ]. destructAll.
        eapply preord_res_monotonic. eassumption. omega.
      * clear. firstorder.
      * clear. firstorder. split; eauto.

        Grab Existential Variables. eauto. eauto. eauto. eauto. (* Not sure where this comes from *)
  Qed.  
  
  (* Adequacy, divergence *)

  Lemma preord_exp_n_preserves_divergence n e1 e2 rho1 rho2 :
    Pr_implies_post_upper_bound post_prop ->
    closed_exp e1 ->
    
    preord_exp_n n e1 e2 ->
    diverge cenv rho1 e1 -> 
    diverge cenv rho2 e2.
  Proof. 
    intros Hrel Hef Hexp Hdiv. induction Hexp.
    - eapply logical_relations.preord_exp_preserves_divergence. eapply Hrel. eassumption.
      intros k. eapply H.
      unfold closed_exp in Hef. rewrite Hef. now intros z Hin; inv Hin.
      eassumption.
    - eapply IHHexp. eapply Hwf_c. eassumption. eassumption.
      eapply logical_relations.preord_exp_preserves_divergence. eapply Hrel. eassumption.
      intros k. eapply H.
      unfold closed_exp in Hef. rewrite Hef. now intros z Hin; inv Hin.
      eassumption.
  Qed.

  
  Lemma preord_exp_n_preserves_not_stuck n e1 e2 rho1 rho2  :
    Pr_implies_post_upper_bound post_prop ->
    closed_exp e1 ->
    
    preord_exp_n n e1 e2 ->
    not_stuck cenv rho1 e1 ->    
    not_stuck cenv rho2 e2.
  Proof.
    intros Piml Hwfe Hexp Hns. inv Hns.
    - destructAll. eapply preord_exp_n_impl in Hexp; [| eassumption | eassumption ].
      destructAll. destruct x2; eauto.
      eapply preord_res_n_OOT_r in H1. contradiction.
      left. eauto.
    - right. eapply preord_exp_n_preserves_divergence; eassumption.
  Qed.
  
  
  (* Top-level relation for L6 pipeline *)
  Definition R_n_exp P PG n m : relation exp :=
    compose_rel (preord_exp_n n)
                (compose_rel (fun e1 e2 =>
                                wf_pres e1 e2 /\ 
                                forall k rho1 rho2 ,
                                  cc_approx_env_P cenv ctag (occurs_free e1) k PG rho1 rho2 ->
                                  cc_approx_exp cenv ctag k P PG (e1, rho1) (e2, rho2))
                             (preord_exp_n m)).

  
  Definition R_n_res PG n m : relation res :=
    compose_rel (preord_res_n n)
                (compose_rel (fun c1 c2 => forall k, cc_approx_res (cc_approx_val cenv ctag) k PG c1 c2)
                             (preord_res_n m)).
  
  Definition R_n_val PG n m : relation val :=    
    compose_rel (preord_val_n n)
                (compose_rel (fun (c1 : val) (c2 : val) => forall k, cc_approx_val cenv ctag k PG c1 c2)
                             (preord_val_n m)).

  
  Lemma preord_exp_n_wf_pres n e1 e2 {_ : Transitive wf_pres} : 
    preord_exp_n n e1 e2 ->
    wf_pres e1 e2.
  Proof.
    intros Hn. induction Hn; eauto.
  Qed.


  Context {Htr : Transitive wf_pres}.
  
  (* Adequacy, termination *)
  
  Lemma R_n_exp_impl P PG (n m : nat) e1 rho1 e2 rho2 :    
    closed_exp e1 ->
    Pr_implies_post_upper_bound post_prop ->    
    R_n_exp P PG n m e1 e2 ->
      
    forall (v1 : res) cin cout,
      bstep_fuel cenv rho1 e1 cin v1 cout ->
      exists (v2 : res) cin' cout',
        bstep_fuel cenv rho2 e2 cin' v2 cout' /\
        R_n_res PG n m v1 v2.
  Proof.
    intros Hwfe Himpl Hrel. inv Hrel. destructAll. inv H0. destructAll. 
    assert (Hexp1 := H). assert (Hexp2 := H2). intros.
    eapply preord_exp_n_impl in H; [| eassumption | eassumption ]. destructAll. 
    edestruct (H2 (to_nat x2) rho1 rho2); [ | | eassumption | ].
    intros z Hin. eapply Hwf_c in Hin. now inv Hin. eapply preord_exp_n_wf_pres. eassumption. eassumption. eassumption.
    omega.
    
    destructAll.

    assert (H5' := H5). 
    eapply preord_exp_n_impl in H5; [| | eassumption ]. destructAll.

    do 3 eexists. split. eassumption.
    
    eexists. split. eassumption. eexists.
    split. 2:{ eassumption. } 
    
    intros k. 
    destruct v1.
    - destruct x1.
      * destruct x4; eauto. 
      * eapply preord_res_n_OOT_l in H4. contradiction.
    - destruct x1.
      + eapply preord_res_n_OOT_r in H4. contradiction.
      + destruct x4; eauto.
        destruct x7. eapply preord_res_n_OOT_r in H8.
        contradiction.
        
        edestruct (H2 (k + to_nat x2)); [| | eassumption | ]. 
         
        eapply cc_approx_env_P_antimon; [| eapply Hwf_c; eauto ].
        intros z Hin. now inv Hin.
        eapply preord_exp_n_wf_pres. eassumption. eassumption. omega. 
        destructAll.
        
        destruct x1. contradiction.
        
        eapply bstep_fuel_deterministic in H9; [| clear H9; eassumption ]. destructAll.
        eapply cc_approx_res_monotonic. eassumption. omega.

    - eapply Hwf_c; eauto. eapply Hwf_c; eauto. eapply preord_exp_n_wf_pres; eauto.

  Qed.

  
  (* R_n_exp preserves divergence *)
  Lemma R_n_exp_preserves_divergence P PG n m e1 rho1 e2 rho2 (Htrans : Transitive wf_pres ):
    Pr_implies_post_upper_bound post_prop ->
    post_upper_bound P ->
    closed_exp e1 ->
    R_n_exp P PG n m e1 e2 ->
    diverge cenv rho1 e1 -> 
    diverge cenv rho2 e2.
  Proof.
    intros Hpr Hp Hc Hrel Hdiv. inv Hrel. destructAll. inv H0. destructAll. 
    eapply preord_exp_n_preserves_divergence; [| | eassumption | ]; eauto. 
    eapply Hwf_c. eapply Htrans; [| eassumption ]. eapply preord_exp_n_wf_pres. eassumption.
    eassumption. eassumption.
    
    eapply cc_approx_exp_preserves_divergence.
    2:{ intros. eapply H2.
        eapply cc_approx_env_P_antimon; [| eapply Hwf_c; eauto ]. intros z Hin. now inv Hin.
        eapply preord_exp_n_wf_pres. eassumption. eassumption. }
    eassumption.
    
    eapply preord_exp_n_preserves_divergence. eapply Hpr. eassumption. eassumption. eassumption.

    Grab Existential Variables. eauto. eauto. 
  Qed.

End RelComp.

Section Linking.
  
  Context (lft: fun_tag).
  Context (cenv : ctor_env) (ctag : ctor_tag).


  Definition link (x : var) (e1 e2 : exp) : exp :=
    let f := (max_var e1 (max_var e2 x) + 1)%positive in
    Efun (Fcons f lft [] e1 Fnil)                               
    (Eletapp x f lft [] e2).
  

  Lemma link_closed x e1 e2 :
    closed_exp e1 ->
    occurs_free e2 \subset [set x] ->
    closed_exp (link x e1 e2).
  Proof.
    intros Hc Hs. unfold closed_exp, link. repeat normalize_occurs_free.
    rewrite !Setminus_Union_distr. repeat rewrite FromList_nil at 1.
    repeat normalize_sets. simpl. repeat rewrite Union_Empty_set_neut_r at 1.
    unfold closed_exp in Hc. rewrite !Hc. repeat normalize_sets.
    rewrite Setminus_Same_set_Empty_set. repeat normalize_sets.
    sets. 
  Qed.

  Context {Hf : @fuel_resource fuel} {Ht : @trace_resource trace}.

  Context (P : PostT) (PG : PostGT) (Hpr : Post_properties cenv P P PG).

  Lemma preord_exp_preserves_linking x e1 e2 e1' e2' :
    
    (forall k rho1 rho2,
        preord_exp cenv P PG k (e1, rho1) (e2, rho2)) ->
    
    (forall k rho1 rho2,
        preord_env_P cenv PG [set x] k rho1 rho2 ->                
        preord_exp cenv P PG k (e1', rho1) (e2', rho2)) ->
    
    closed_exp e1 ->

    forall k rho1 rho2, preord_exp cenv P PG k (link x e1 e1', rho1) (link x e2 e2', rho2).
  Proof.
    intros Hexp1 Hexp2 Hc1. inv Hpr.
    unfold link in *.
    intros k rho1 rho2.

    
    eapply preord_exp_fun_compat.
    - now eauto.
    - now eauto.
    - eapply preord_exp_letapp_compat.
      + now eauto.
      + now eauto.
      + now eauto.
      + simpl. intros w Hget. rewrite M.gss in Hget. inv Hget. 
        eexists. rewrite M.gss. split. reflexivity. 
        rewrite preord_val_eq. intros vs1 vs2 j t xs1 eb rho1' Hlen Hdef Hset1.
        simpl in *. rewrite peq_true in Hdef. inv Hdef. simpl in Hset1. destruct vs1. 2:{ congruence. }
        inv Hset1.
        destruct vs2; [| simpl in *; congruence ].
        rewrite peq_true. do 3 eexists. split. reflexivity. split. reflexivity.
        intros. eapply (Hexp1 j) in H2; [| omega ]. destructAll. do 3 eexists. split. eassumption.
        split. eapply HGPost. eassumption. eassumption. 
      + now constructor.
      + intros. eapply Hexp2.
        simpl. intros w1 Hget. inv Hget. intros v3 Hget1. rewrite M.gss in *. inv Hget1.
        eauto.
  Qed. 



  Lemma cc_approx_exp_preserves_linking x e1 e2 e1' e2' :
    
    (forall k rho1 rho2,
        cc_approx_exp cenv ctag k P PG (e1, rho1) (e2, rho2)) ->
    
    (forall k rho1 rho2,
        cc_approx_env_P cenv ctag [set x] k PG rho1 rho2 ->                
        cc_approx_exp cenv ctag k P PG (e1', rho1) (e2', rho2)) ->
    
    closed_exp e1 ->
    
    forall k rho1 rho2, cc_approx_exp cenv ctag k P PG (link x e1 e1', rho1) (link x e2 e2', rho2).
  Proof.
    intros Hexp1 Hexp2 Hc1. inv Hpr.
    unfold link in *.
    intros k rho1 rho2.

    
    eapply cc_approx_exp_fun_compat.
    - now eauto.
    - now eauto.
    - intros v1 cin1 cout1 Hlt Hbstep. inv Hbstep.
      + (* OOT *)
        eexists OOT, cin1, <0>. split; [| split ].
        econstructor. eassumption. eapply HPost_OOT. eassumption.
        simpl; eauto.
      + inv H.
        * simpl in *. inv H7.
          destruct xs; [| simpl in H12; congruence ]. simpl in *. inv H12.
          rewrite M.gss in *. inv H5. simpl in *. rewrite peq_true in *. inv H11. 

          edestruct (Hexp1 (k + to_nat cin1 + to_nat cin2)); try eassumption. omega. 
          destructAll. destruct x0. contradiction. 
          
          edestruct (Hexp2 (k + to_nat cin2)); try eassumption.
          2:{ omega. }
          
          2:{ destructAll.
              do 3 eexists. split. econstructor 2. econstructor.
              simpl. rewrite M.gss. reflexivity. simpl. reflexivity. simpl. rewrite peq_true.
              reflexivity. simpl. reflexivity. eassumption. eapply H2.
              split.
              eapply HPost_letapp; eauto. rewrite M.gss. reflexivity.  reflexivity.
              simpl. rewrite peq_true. reflexivity. reflexivity.
              eapply cc_approx_res_monotonic. eassumption. rewrite !to_nat_add. omega. }

          simpl. intros w1 Hget. inv Hget. intros v3 Hget1. rewrite M.gss in *. simpl in *. inv Hget1.
          eexists. split; eauto.
          eapply cc_approx_val_monotonic. eassumption. omega.
        * simpl in *. inv H10.
          destruct xs; [| simpl in H12; congruence ]. simpl in *. inv H12.
          rewrite M.gss in *. inv H6. simpl in *. rewrite peq_true in *. inv H11. 
          
          edestruct (Hexp1 (k + to_nat cin)); try eassumption. omega. 
          destructAll. destruct x0. 2:{ contradiction. }

          do 3 eexists. split. econstructor 2. eapply BStept_letapp_oot.
          simpl. rewrite M.gss. reflexivity. simpl. reflexivity. simpl. rewrite peq_true.
          reflexivity. simpl. reflexivity. eapply H.
          split.
          eapply HPost_letapp_OOT; eauto. rewrite M.gss. reflexivity.  reflexivity.
          simpl. rewrite peq_true. reflexivity. reflexivity.

          eauto.
  Qed. 

  

  Context (wf_pres : exp -> exp -> Prop) (post_prop : post_property).
    


  Lemma preord_exp_n_1 Pr e1 e2 :
    preord_exp_n cenv wf_pres Pr 1 e1 e2 ->
    exists P PG,
      Pr P PG /\
      wf_pres e1 e2 /\
      (forall k rho1 rho2,
          preord_env_P cenv PG (occurs_free e1) k rho1 rho2 ->
          preord_exp cenv P PG k (e1, rho1) (e2, rho2)).
  Proof.
    intros H. inv H. do 2 eexists. now split; eauto.
    inv H2. 
  Qed.

  (* Lemma preord_exp_n_wf_monotonic (wf1 wf2 : exp -> Prop) P1 Pr e1 e2 : *)
  (*   (forall e, wf1 e -> wf2 e) -> *)
  (*   preord_exp_n cenv wf1 Pr 1 P1 e1 e2 -> *)
  (*   preord_exp_n cenv wf2 Pr 1 P1 e1 e2. *)
  (* Proof. *)
  (*   intros. induction H0. *)
  (*   - constructor; eauto. *)
  (*   - econstructor; eauto. *)
  (* Qed. *)
  
End Linking.

Section LinkingComp.
      
  Context (Pr : post_property)
          (wf_pres : exp -> exp -> Prop)
          (cenv : ctor_env) (lf : var).

  Context {Hf : @fuel_resource fuel} {Ht : @trace_resource trace}.

  Context (Hwf : forall e e', wf_pres e e' -> preserves_fv e e')
          (Hpr : forall P PG, Pr P PG -> Post_properties cenv P P PG).
  
   
  Lemma inclusion_refl {A} (Q : relation A) : inclusion _ Q Q.
  Proof. clear. now firstorder. Qed.

  Definition preserves_closed (e1 e2 : exp) := closed_exp e1 -> closed_exp e2.

  Lemma preord_exp_n_preserves_linking_src_l x n e1 e2 e1' :
    preord_exp_n cenv preserves_closed Pr n e1 e2 ->
    
    closed_exp e1 ->
    occurs_free e1' \subset [set x] ->
    
    preord_exp_n cenv preserves_closed Pr n (link lf x e1 e1') (link lf x e2 e1').
  Proof.
    intros Hrel. revert e1'. induction Hrel; intros e1' Hw1 Hfv.
    - assert (Hexp2 :
                forall k rho1 rho2,
                  preord_env_P cenv P2 [set x] k rho1 rho2 ->
                  preord_exp cenv P1 P2 k (e1', rho1) (e1', rho2)).
      { intros. eapply preord_exp_refl. eapply Hpr. eassumption.
        intros z Hin. eapply Hfv in Hin . eauto. } 
      assert (Hexp1 :
                forall (k : nat) (rho1 rho2 : env),
                  preord_exp' cenv (preord_val cenv) P1 P2 k (c1, rho1) (c2, rho2)).
      { intros. eapply H. intros z Hin. eapply Hw1 in Hin; eauto. inv Hin. }
      
      
      specialize (preord_exp_preserves_linking
                    lf cenv P1 P2 (Hpr _ _ H1) _ _ _ _ _ Hexp1 Hexp2 Hw1).
      intros Hc. 
      econstructor. 
      * intros. eapply Hc.
      * intros Hc1. eapply link_closed; [| eassumption ]. eapply H0. eassumption.
      * eassumption.
    - assert (Hc' : closed_exp c'). { eapply H0. eassumption. }
      specialize (IHHrel e1' Hc' Hfv).

      assert (Hexp1 :
                forall (k : nat) (rho1 rho2 : env),
                  preord_exp' cenv (preord_val cenv) P1 P2 k (c1, rho1) (c', rho2)).
      { intros. eapply H. intros z Hin. eapply Hw1 in Hin; eauto. inv Hin. } 
      assert (Hexp2 :
                forall k rho1 rho2,
                  preord_env_P cenv P2 [set x] k rho1 rho2 ->
                  preord_exp cenv P1 P2 k (e1', rho1) (e1', rho2)).
      { intros. eapply preord_exp_refl. eapply Hpr. eassumption.
        intros z Hin. eapply Hfv in Hin . eauto. }
      
      econstructor; [| | | eassumption ].
      + specialize (preord_exp_preserves_linking
                      lf cenv P1 P2 (Hpr _ _ H1) _ _ _ _ _ Hexp1 Hexp2 Hw1).
        intros Hc.
        intros. eapply Hc.
      + eapply IHHrel; eauto.
      + intros Hc1. eapply link_closed; [| eassumption ]. eapply H0. eassumption.
  Qed.    

  Lemma preord_exp_n_preserves_linking_src_r x n e1 e1' e2' :  
    preord_exp_n cenv preserves_fv Pr n e1' e2' ->
    
    closed_exp e1 ->
    occurs_free e1' \subset [set x] ->
    
    preord_exp_n cenv preserves_closed Pr n (link lf x e1 e1') (link lf x e1 e2').
  Proof.
    intros Hrel. revert e1. induction Hrel; intros e1 Hw1 Hfv.
    - assert (Hexp2 :
                forall k rho1 rho2,
                  preord_env_P cenv P2 [set x] k rho1 rho2 ->
                  preord_exp cenv P1 P2 k (c1, rho1) (c2, rho2)).
      { intros. eapply H. intros z Hin. eapply Hfv in Hin; eauto. }
      
      assert (Hexp1 :
                forall (k : nat) (rho1 rho2 : env),
                  preord_exp' cenv (preord_val cenv) P1 P2 k (e1, rho1) (e1, rho2)).
      { intros. eapply preord_exp_refl. eapply Hpr. eassumption.
        intros z Hin. eapply Hw1 in Hin. inv Hin. } 
      
      specialize (preord_exp_preserves_linking
                    lf cenv P1 P2 (Hpr _ _ H1) _ _ _ _ _ Hexp1 Hexp2 Hw1).
      intros Hc.
      econstructor. 
      * intros. eapply Hc.
      * intros Hc1. eapply link_closed. eassumption.
        eapply Included_trans. eapply H0. eassumption. 
      * eassumption.
    - assert (Hc' : occurs_free c' \subset [set x]). { eapply Included_trans. eapply H0. eassumption. }
      specialize (IHHrel e1 Hw1 Hc').
      
      assert (Hexp2 :
                forall k rho1 rho2,
                  preord_env_P cenv P2 [set x] k rho1 rho2 ->
                  preord_exp cenv P1 P2 k (c1, rho1) (c', rho2)).
      { intros. eapply H. intros z Hin. eapply Hfv in Hin; eauto. }
      
      assert (Hexp1 :
                forall (k : nat) (rho1 rho2 : env),
                  preord_exp' cenv (preord_val cenv) P1 P2 k (e1, rho1) (e1, rho2)).
      { intros. eapply preord_exp_refl. eapply Hpr. eassumption.
        intros z Hin. eapply Hw1 in Hin. inv Hin. }

      econstructor; [| | | eassumption ].
      + specialize (preord_exp_preserves_linking
                      lf cenv P1 P2 (Hpr _ _ H1) _ _ _ _ _ Hexp1 Hexp2 Hw1).
        intros Hc.
        intros. eapply Hc.
      + eapply IHHrel; eauto.
      + intros Hc1. eapply link_closed; [| eassumption ]. eassumption.
  Qed.

  Lemma preord_exp_n_trans n m e1 e2 e3 :         
    preord_exp_n cenv preserves_closed Pr n e1 e2 ->
    preord_exp_n cenv preserves_closed Pr m e2 e3 ->
    preord_exp_n cenv preserves_closed Pr (n + m) e1 e3.
  Proof.
    intros H1 H2. induction H1. 
    - econstructor; try eassumption.
    - simpl. econstructor.
      + eassumption.
      + eapply IHR_n. eassumption.
      + eassumption.
      + eassumption.
  Qed.
  
  Lemma preord_exp_n_preserves_linking x n m e1 e2 e1' e2' :
    preord_exp_n cenv preserves_closed Pr n e1 e2 ->
    preord_exp_n cenv preserves_fv Pr m e1' e2' ->
    
    closed_exp e1 ->
    occurs_free e1' \subset [set x] ->
    
    preord_exp_n cenv preserves_closed Pr (n + m) (link lf x e1 e1') (link lf x e2 e2').
  Proof.
    intros (* Hp1 Hp2 *) Hrel1 Hrel2 Hc1 Hfv.
    specialize (preord_exp_n_preserves_linking_src_l x n _ _ _ Hrel1 Hc1 Hfv). intros Hr1.
    eapply preord_exp_n_trans. eassumption.
    
    assert (Hc2 : closed_exp e2). {
      eapply preord_exp_n_wf_pres in Hrel1. eapply Hrel1. eassumption.
      clear. firstorder. }

    eapply preord_exp_n_preserves_linking_src_r. eassumption. eassumption. eassumption.
  Qed.        

End LinkingComp.

Section LinkingCompTop.

  Context (Pr : post_property)
          (wf_pres : exp -> exp -> Prop)
          (wf1 wf2 : exp -> Prop)          
          (cenv : ctor_env) (ctag : ctor_tag) (lf : var) (P : PostT) (PG : PostGT).

  Context {Hf : @fuel_resource fuel} {Ht : @trace_resource trace}.
    
  Context (Hwf : forall e e', wf_pres e e' -> preserves_fv e e')
          (Hpr : forall P PG, Pr P PG -> Post_properties cenv P P PG)
          (Hp : Post_properties cenv P P PG).

  
  Lemma preord_exp_n_prop_mon (Pt1 Pt2 : post_property) n e1 e2 :
    preord_exp_n cenv wf_pres Pt1 n e1 e2 ->
    (forall P PG, Pt1 P PG -> Pt2 P PG) ->
    preord_exp_n cenv wf_pres Pt2 n e1 e2.
  Proof.
    intros Hrel Hi. induction Hrel.
    - econstructor; eauto.
    - econstructor; eauto.
  Qed.
  
  Lemma Rel_exp_n_preserves_linking x n1 n2 m1 m2 e1 e2 e1' e2' :    
    R_n_exp cenv ctag preserves_closed Pr P PG n1 n2 e1 e2 ->
    R_n_exp cenv ctag preserves_fv Pr P PG m1 m2 e1' e2' ->

    (* e1: source library, e2: compiled library *)
    (* e1': source client, e2': compiled client *)    
    
    closed_exp e1 ->
    occurs_free e1' \subset [set x] ->
    
    R_n_exp cenv ctag preserves_closed Pr P PG (n1 + m1) (n2 + m2) (link lf x e1 e1') (link lf x e2 e2').
  Proof.
    
    intros Hrel1 Hrel2 Hc1 Hfv. inv Hrel1. inv Hrel2. destructAll. inv H1. inv H2. destructAll.  
    
    assert (Hc2 : closed_exp x0). {
      eapply preord_exp_n_wf_pres in H. eapply H in Hc1. eassumption. clear. now firstorder. }
    assert (Hfv2 : occurs_free x1 \subset [set x]).
    { eapply preord_exp_n_wf_pres in H0. eapply Included_trans. eapply H0; eauto. eassumption.
      clear. now firstorder. }
    assert (Hc3 : closed_exp x3).
    { eapply H1. eassumption. }
    assert (Hfv3 : occurs_free x3 \subset [set x]).
    { eapply Included_trans. eapply H1. eassumption. sets. }
    assert (Hfv3' : occurs_free x2 \subset [set x]).
    { eapply Included_trans. eapply H3. eassumption. }

    
    eexists. split.
    
    eapply preord_exp_n_preserves_linking; eassumption. 
    
    eexists. split. split.
    2:{ intros. eapply cc_approx_exp_preserves_linking.
        2:{ intros. eapply H4. intros z Hin. eapply preord_exp_n_wf_pres in H. eapply H in Hin. inv Hin.
            eassumption. clear; now firstorder. }
        eassumption.

        intros. eapply H6. intros z Hin. eapply H8. eapply Hfv2. eassumption. eassumption. }

    intros Hc. eapply link_closed. eassumption.
    eapply Included_trans. eapply H3. eassumption.

    eapply preord_exp_n_preserves_linking; eassumption.
  Qed.

End LinkingCompTop.

Section LinkingFast.
  
  Context (lft: fun_tag).
  Context (cenv : ctor_env) (ctag : ctor_tag).
    
  Definition link' (x : var) (* the external reference that will be bound to e1 *)
             (e1 e2 : exp) : option exp :=
    match inline_letapp e1 x with
    | Some (C, x') =>
      let f := (max_var e1 (max_var e2 x') + 1)%positive in
      (* pick fresh name for function *) 
      Some (C |[ Efun (Fcons f lft [x] e1 Fnil) (Eapp f lft [x'])]|)
    | None => None
    end.
    
  Lemma link_straight_code_r x (e1 e2 e : exp) :
    link' x e1 e2 = Some e ->
    straight_code e1 = true.
  Proof.
    unfold link' in *. intros H.
    match goal with
    | [ Hin : context[inline_letapp ?E ?X] |- _ ] => 
      destruct (inline_letapp E X) as [[C' w] | ] eqn:Hin'; inv Hin
    end. eapply inline_straight_code_r. eassumption.
  Qed.
  
  Lemma link_straight_code_l (e1 e2 : exp) x :
    straight_code e1 = true ->
    exists e, link' x e1 e2 = Some e.
  Proof.
    intros. eapply inline_straight_code_l in H. destructAll.
    eexists. unfold link'. rewrite H. reflexivity.
  Qed.


  Lemma link_src_closed x e1 e2 e :
    closed_exp e1 ->
    occurs_free e2 \subset [set x] ->
    link' x e1 e2 = Some e ->
    closed_exp e.
  Proof.
    intros Hc1 Hc2 Hin. unfold link' in *.    
    destruct (inline_letapp e1 x) as [[C z] | ] eqn:Hinl1; try congruence. inv Hin.
    split; [| now sets ].
    eapply Included_trans. eapply occurs_fee_inline_letapp; eauto.
    eapply Union_Included. now eapply Hc1. 
    unfold closed_exp in Hc1. repeat normalize_occurs_free.
    simpl in *. repeat normalize_sets.
    rewrite !Setminus_Union_distr in *. rewrite !Setminus_Same_set_Empty_set in *. repeat normalize_sets.
    eapply Union_Included.
    - rewrite Hc1. sets.
    - rewrite Setminus_Union. rewrite Union_commut. rewrite <- Setminus_Union.
      eapply Included_trans. eapply Setminus_Included.
      eapply inline_letapp_var_eq_alt in Hinl1. inv Hinl1.
      + inv H. intros z H. inv H. inv H0. contradiction.
      + inv H.
        * intros y H. inv H. inv H1. contradiction.
        * eapply Hc1 in H0. inv H0.
  Qed.
  

  Context {Hf : @fuel_resource fuel} {Ht : @trace_resource trace}.

  Context (P : PostT) (PG : PostGT) (Hpr : Post_properties cenv P P PG)
          (Hinl : post_inline cenv P P P)
          (HinlOOT : post_inline_OOT P P)
          (HinclG : inclusion _ P PG) .
  
  
  Lemma preord_exp_preserves_linking_fast x e1 e2 e1' e2' :
    
    (forall k rho1 rho2,
        preord_exp cenv P PG k (e1, rho1) (e2, rho2)) ->
    
    (forall k rho1 rho2,
        preord_env_P cenv PG [set x] k rho1 rho2 ->                
        preord_exp cenv P PG k (e1', rho1) (e2', rho2)) ->
    
    closed_exp e1 ->
    
    match link' x e1 e1', link' x e2 e2' with
    | Some e, Some e' =>
      forall k rho1 rho2, preord_exp cenv P PG k (e, rho1) (e', rho2)
    | _ , _ => True
    end.
  Proof.
    intros Hexp1 Hexp2 (* Hc1 *) Hc1. inv Hpr.
    unfold link' in *.
    
    destruct (inline_letapp e1 x) as [[C z] | ] eqn:Hinl1; eauto.
    destruct (inline_letapp e2 x) as [[C' z'] | ] eqn:Hinl2; eauto.
    
    intros k rho1 rho2.
    eapply inline_letapp_compat with (sig := id); [ | | | eapply Hc1 | eassumption | eassumption  | ].
    - eassumption.
    - eassumption.
    - intros. eapply Hexp1.
    - intros. eapply preord_exp_fun_compat.
      + eauto.
      + eauto.
      + eapply preord_exp_app_compat.
        * now eauto.
        * now eauto.
        * simpl. intros w Hget. rewrite M.gss in Hget. inv Hget. 
          eexists. rewrite M.gss. split. reflexivity. 
          rewrite preord_val_eq. intros vs1 vs2 j t xs1 eb rho1' Hlen Hdef Hset1.
          simpl in *. rewrite peq_true in Hdef. inv Hdef. simpl in Hset1. destruct vs1. congruence.
          destruct vs1; [| congruence ]. inv Hset1. destruct vs2. simpl in *. congruence.
          destruct vs2; [| simpl in *; congruence ].
          rewrite peq_true. do 3 eexists. split. reflexivity. split. reflexivity.
          intros. eapply (Hexp1 j) in H4; [| omega ]. destructAll. do 3 eexists. split. eassumption.
          split. eapply HinclG. eassumption. eassumption. 
        * assert (Hleq : (z' <= max_var e2 (max_var e2' z'))%positive).
          { eapply Pos.le_trans. eapply acc_leq_max_var. eapply acc_leq_max_var. }
          assert (Hleq' : (z <= max_var e1 (max_var e1' z))%positive).
          { eapply Pos.le_trans. eapply acc_leq_max_var. eapply acc_leq_max_var. }
          
          constructor; [| now constructor ].          
          simpl. intros w1 Hget.
          rewrite M.gso in Hget; auto. 
          rewrite M.gso; auto.
          eapply H0 in Hget; [| reflexivity ]. destructAll.
          rewrite functions.extend_gss in H1. 
          eexists. split; eauto. eapply preord_val_monotonic. eassumption. omega.
          
          intros Hc. rewrite Hc in Hleq at 1. zify; omega.
          intros Hc. rewrite Hc in Hleq' at 1. zify; omega.
  Qed.

  Lemma cc_approx_exp_preserves_linking_fast x e1 e2 e1' e2' (Hincl : inclusion _ P PG):
    
    (forall k rho1 rho2,
        cc_approx_exp cenv ctag k P PG (e1, rho1) (e2, rho2)) ->
    
    (forall k rho1 rho2,
        cc_approx_env_P cenv ctag [set x] k PG rho1 rho2 ->                
        cc_approx_exp cenv ctag k P PG (e1', rho1) (e2', rho2)) ->
    
    closed_exp e1 ->
    
    match link' x e1 e1', link' x e2 e2' with
    | Some e, Some e' =>
      forall k rho1 rho2, cc_approx_exp cenv ctag k P PG (e, rho1) (e', rho2)
    | _ , _ => True
    end.
  Proof.
    intros Hexp1 Hexp2 (* Hc1 *) Hc1. inv Hpr.
    unfold link' in *.
    
    destruct (inline_letapp e1 x) as [[C z] | ] eqn:Hinl1; eauto.
    destruct (inline_letapp e2 x) as [[C' z'] | ] eqn:Hinl2; eauto.
    
    intros k rho1 rho2.
    eapply inline_letapp_compat_cc with (sig := id); [ | | | eapply Hc1 | eassumption | eassumption  | ].
    - eassumption.
    - eassumption.
    - intros. eapply Hexp1.
    - intros. eapply cc_approx_exp_fun_compat.
      + eauto.
      + eauto.
      + simpl def_funs. intros v1 c1 c2 Hleq Hstep. inv Hstep.
        * eexists OOT, c1. eexists. split; [| split ].
          -- econstructor. simpl in *. eassumption.
          -- simpl. eapply HPost_OOT. eassumption.
          -- simpl. eauto.
        * inv H1. simpl in *. rewrite M.gss in *. inv H5. simpl in H8.
          rewrite peq_true in H8. inv H8. simpl in H12. destruct vs. congruence.
          destruct vs; [| congruence ]. inv H12.
          assert (Hleqz : (z <= max_var e (max_var e1' z))%positive).
          { eapply Pos.le_trans. eapply acc_leq_max_var. eapply acc_leq_max_var. }
          rewrite M.gso in H6.
          2:{ intros Hc. zify. omega. }
          destruct (rho' ! z) eqn:Hgetz; inv H6.
          edestruct H0. reflexivity. eassumption. destructAll. rewrite functions.extend_gss in H1. 
          
          eapply (Hexp1 (m + 2  + to_nat cin)) in H13; try omega. 
          

          destructAll.
          assert (Hleqz' : (z' <= max_var e2 (max_var e2' z'))%positive).
          { eapply Pos.le_trans. eapply acc_leq_max_var. eapply acc_leq_max_var. }
          do 3 eexists.
          split; [| split ].
          -- constructor 2. econstructor. rewrite M.gss. reflexivity.
             simpl. rewrite M.gso. rewrite H1. reflexivity.
             
             intros Heq.
             zify. omega.
             simpl. rewrite peq_true. reflexivity. simpl. reflexivity. eassumption.
          -- simpl. eapply HGPost in H4.  eapply HPost_app in H4.
             unfold one in *. simpl in *. eassumption. 
             rewrite M.gss. reflexivity. simpl. rewrite M.gso. rewrite Hgetz. reflexivity.
             intros Hc. zify; omega.
             simpl. rewrite peq_true. reflexivity. simpl. reflexivity.
          -- eapply cc_approx_res_monotonic. eassumption. omega.
  Qed.
  
End LinkingFast.
