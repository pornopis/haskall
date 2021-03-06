module Expressions where
import AbsHaskall
import Environment
import PrintHaskall
import Data.Map (Map, insert, lookup, empty, toList, fromList)

import Data.Either
import Data.List

lookupTypeDef :: Env -> Type -> Either TypingError VType
lookupTypeDef env (TFunc args tpt) = case lookupTypeDef env tpt of
    Left err -> Left err
    Right tp -> case lookupTypeDefs env args of
        Left err -> Left err
        Right argTps -> Right $ FuncType argTps tp

lookupTypeDef env (TType (Ident tpn)) =
    case Data.Map.lookup tpn (types env) of
        Nothing -> Left $ UnknownType tpn
        Just tp -> Right tp

lookupTypeDefs _ [] = Right []
lookupTypeDefs env (tpt:rest) = case lookupTypeDef env tpt of
    Left err -> Left err
    Right tp -> case lookupTypeDefs env rest of
        Left err -> Left err
        Right tps -> Right $ tp : tps

compileExpression :: Exp -> Env -> Either TypingError (State -> TryValue)
compileExpression exp env = case typeExp exp env of
        -- Right (expType, typedExp) -> Left $ TypingError $ (show expType) ++ " \n " ++ (printTree typedExp) ++ "\n" ++ (show typedExp)
        Right (expType, typedExp) -> Right $ compExp env typedExp
        Left err -> Left err

-- DECLARATIONS

-- function arguments
addArgument :: ArgDec -> Env -> Either TypingError Env
addArgument (TArgDec (Ident arg) tpt) env =
    case lookupTypeDef env tpt of
        Left err -> Left err
        Right tp -> Right $ createEmptyVar arg tp env

addArguments :: [ArgDec] -> Env -> Either TypingError Env
addArguments [] env = Right env
addArguments (arg:rest) env = case addArgument arg env of
    Left err -> Left err
    Right newEnv -> addArguments rest newEnv

argTypes env [] = Right []
argTypes env (TArgDec (Ident arg) tpt:args) =
    case lookupTypeDef env tpt of
        Left err -> Left err
        Right tp -> case argTypes env args of
            Left err -> Left err
            Right ftps -> Right $ tp:ftps   

argNames args = map (\(TArgDec (Ident arg) _) -> arg) args



-- TYPING

data TypingError = 
    UnexpectedTypeError VType VType Exp
    | ConditionTypingError Exp VType
    | ArgumentTypingError [Exp] [VType] Exp VType
    | AssignmentTypingError String VType Exp VType
    | NotDeclaredError String Env
    | IfTypingError Exp VType VType
    | EqTypingError Exp VType VType
    | NotAFunctionError Exp VType
    | FunctionTypeError Exp VType VType
    | TypingError String
    | AddTypeError Exp VType VType
    | UnknownType String
    | NotMatchable VType
    | NoSuchConstructor String

untype str = Left $ TypingError str

instance Show TypingError where
    show (UnexpectedTypeError expT realT expr) =
        "typing error: expected type " ++ (show expT) ++ " but expression " ++
        (printTree expr) ++ " has type " ++ (show realT)
    show (ConditionTypingError exp tp) = 
        "typing error: expression of type " ++
        (show tp) ++ " as condition in expression: " ++ (printTree exp)
    show (ArgumentTypingError args types fun tp) =
        "cannot apply arguments " ++ (intercalate ", " $ map printTree args)
        ++ " of types " ++ (intercalate ", " $ map show types) ++
        " to function " ++ (printTree fun) ++ " of type " ++ (show tp)
    show (AssignmentTypingError var vtp val vatp) = "cannot assign value "
        ++ (show val) ++ " of type " ++ (show vatp) ++ " to variable " ++ var
        ++ " of type " ++ (show vtp)
    show (NotDeclaredError var env) = "variable " ++ var ++
        " not declared in env: \n" ++ (show env)
    show (IfTypingError exp tp1 tp2) = "typing error: two branches of an if "
        ++ "statement " ++ (printTree exp) ++ " have different types " ++
        (show tp1) ++ " and " ++ (show tp2)
    show (EqTypingError exp tp1 tp2) = "typing error: cannot compare values "
        ++ "of types " ++ (show tp1) ++ " and " ++ (show tp2) ++ " in " ++
        (printTree exp)
    show (NotAFunctionError exp tp) = "typing error: expression " ++
        (printTree exp) ++ " of type " ++ (show tp) ++ " is not a function"
    show (FunctionTypeError exp tp1 tp2) = "typing error: function " ++
        (printTree exp) ++ " declares type " ++ (show tp1) ++ " but has type "
        ++ (show tp2)
    show (TypingError str) = "typing error: " ++ str
    show (AddTypeError exp t1 t2) = "typing error: can not add values of " ++
        "types " ++ (show t1) ++ " and " ++ (show t2) ++ " in expression " ++
        (printTree exp)
    show (UnknownType tp) = "typing error: unknown type " ++ (show tp)
    show (NotMatchable tp) = "typing error: type " ++ (show tp) ++ " is not"
        ++ "matchable in this context"
    show (NoSuchConstructor nm) = "typing error: constructor " ++ nm ++
        " not found"

mapWithExc _ [] = Right []
mapWithExc f (e:rest) = case f e of
    Left err -> Left err
    Right ef -> case mapWithExc f rest of
        Left err -> Left err
        Right efs -> Right $ ef : efs

expectType tp exp env = case typeExp exp env of
    Left err -> Left err
    Right (expType, typedExp) -> if tp == expType
        then Right $ (expType, typedExp)
        else Left $ UnexpectedTypeError tp expType exp

typeBoth e1 e2 t1 t2 tf c env = case expectType t1 e1 env of
    Left err -> Left err
    Right (_, exp1) -> case expectType t2 e2 env of
        Left err -> Left err
        Right (_, exp2) -> Right (tf, c exp1 exp2)

typeExpList :: [Exp] -> Env -> Either TypingError [(VType, Exp)]
typeExpList exps env = let types = map (flip typeExp env) exps in
    case lefts types of
        [] -> Right $ rights types
        lst -> Left $ head lst


foldPats env [] = Right env
foldPats env ((t,pat):rest) = case typePat t pat env of
    Left err -> Left err
    Right penv -> foldPats penv rest

typePat :: VType -> Pattern -> Env -> Either TypingError Env
typePat tp PDef env = Right env
typePat tp (PVar (Ident var)) env = Right $ snd $ addToEnv var tp env
typePat (AlgType tpn constrs) (PCon (Ident cons) pats) env =
    case filter (\(Constr nm _) -> nm == cons) constrs of
        [] -> Left $ NoSuchConstructor cons
        (Constr nm types):_ -> foldPats env (zip types pats)
            
typePat tp _ _ = Left $ NotMatchable tp

typeProd tpi tpf (Prod pat exp) env = case typePat tpi pat env of
    Left err -> Left err
    Right patEnv -> case expectType tpf exp patEnv of
        Left err -> Left err
        Right (expTp, tpExp) -> Right $ Prod pat tpExp

typeProds tpi tpf [] env = Right []
typeProds tpi tpf (pr:rest) env = case typeProd tpi tpf pr env of
    Left err -> Left err
    Right prf -> case typeProds tpi tpf rest env of
        Left err -> Left err
        Right prfs -> Right $ prf:prfs

-- check whether expression types properly in env and returns the type and
-- full-typed version of this expression
typeExp :: Exp -> Env -> Either TypingError (VType,Exp)

typeExp (EMatch exp tpt prods) env = case typeExp exp env of
    Left err -> Left err
    Right (expTp, tpExp) -> case lookupTypeDef env tpt of
        Left err -> Left err
        Right tpf -> case typeProds expTp tpf prods env of
            Left err -> Left err
            Right prodsf -> Right (tpf, EMatch tpExp tpt prodsf)

typeExp (EIf cond e1 e2) env = case typeExp cond env of
    Left err -> Left err
    Right (condType, typedCond) -> if condType /= BoolType
        then Left $ ConditionTypingError (EIf cond e1 e2) condType
        else case (typeExp e1 env, typeExp e2 env) of
            (Left err, _) -> Left err
            (_, Left err) -> Left err
            (Right (type1, exp1), Right (type2, exp2)) -> if type1 == type2
                then Right (type1, EIf typedCond exp1 exp2)
                else Left $ IfTypingError (EIf cond e1 e2) type1 type2


typeExp (ELt e1 e2) env = typeBoth e1 e2 IntType IntType BoolType ELt env
typeExp (EEq e1 e2) env = case (typeExp e1 env, typeExp e2 env) of
    (Right (type1, exp1), Right (type2, exp2)) -> case (type1,type2) of
        (IntType,IntType)   -> Right (BoolType, EEq exp1 exp2)
        (BoolType,BoolType) -> Right (BoolType, EEq exp1 exp2)
        (StringType,StringType) -> Right (StringType, EEq exp1 exp2)
        _ -> Left $ EqTypingError (EEq e1 e2) type1 type2
    (Left err, _) -> Left err
    (_, Left err) -> Left err

typeExp (EFunc args tpt exp) env =
    case argTypes env args of
        Left err -> Left err
        Right argTps -> case addArguments args env of
            Left err -> Left err
            Right funEnv -> case lookupTypeDef env tpt of
                Left err -> Left err
                Right eType -> case typeExp exp funEnv of
                    Left err -> Left err
                    Right (funType, typedExp) -> if funType == eType
                        then Right (FuncType argTps eType,
                                    EFunc args tpt typedExp)
                        else Left $ FunctionTypeError (EFunc args tpt exp)
                                        eType funType

typeExp (ENFunc (Ident fun) args tpt exp) env = 
    case argTypes env args of
        Left err -> Left err
        Right atypes -> case lookupTypeDef env tpt of
            Left err -> Left err
            Right tp -> let
                    (_, funEnv) = addToEnv fun (FuncType atypes tp) env
                in case typeExp (EFunc args tpt exp) funEnv of
                    Left err -> Left err
                    Right (funType, (EFunc args tp exp)) ->
                        Right (funType, ENFunc (Ident fun) args tp exp)

typeExp (Call funExp args) env = case typeExp funExp env of
    Left err -> Left err
    Right (FuncType types retTp, typedFunExp) -> case typeExpList args env of
        Left err -> Left err
        Right argTpList -> let (argTypes, typedArgs) = unzip argTpList in
            if argTypes == types
                then Right $ (retTp, Call typedFunExp typedArgs)
                else Left $ ArgumentTypingError args argTypes funExp (FuncType types retTp)
    Right (tp, exp) -> Left $ NotAFunctionError exp tp


typeExp (ELet [] exp) env = case typeExp exp env of
    Left err -> Left err
    Right (expTp, tpExp) -> Right $ (expTp, ELet [] tpExp)

typeExp (ELet (dh:decls) exp) env = let
        typeDecl (FSUnTDec (Ident var) varExp) =
            case typeExp varExp env of
                Left err -> Left err
                Right (expTp, tpExp) ->
                        Right $ (snd $ addToEnv var expTp env,
                                FSTDec (Ident var) (typeToToken expTp) tpExp)
        typeDecl (FSTDec (Ident var) varTpt varExp) =
            case lookupTypeDef env varTpt of
                Left err -> Left err
                Right varTp -> case expectType varTp varExp env of
                    Left err -> Left err
                    Right (expTp, tpExp) ->
                        Right $ (snd $ addToEnv var expTp env,
                                FSTDec (Ident var) (typeToToken expTp) tpExp)
        typeDecl (FSAlias (Ident ntnm) tpt) = case lookupTypeDef env tpt of
            Left err -> Left err
            Right tp -> Right (addType ntnm tp env, FSAlias (Ident ntnm) tpt)
    in case typeDecl dh of
        Left err -> Left err
        Right (letEnv, tpDecl) ->
            case typeExp (ELet decls exp) letEnv of
                Left err -> Left err
                Right (letTp, ELet fdecls fexp) ->
                    Right $ (letTp, ELet (tpDecl:fdecls) fexp)


typeExp (EAdd e1 e2) env = case (typeExp e1 env, typeExp e2 env) of
    (Left err,_) -> Left err
    (_,Left err) -> Left err
    (Right(tp1,te1), Right(tp2,te2)) -> case (tp1,tp2) of
        (IntType,IntType) -> Right (IntType, EAdd te1 te2)
        (StringType,StringType) -> Right (StringType, EAdd te1 te2)
        _ -> Left $ AddTypeError (EAdd te1 te2) tp1 tp2

typeExp (ESub e1 e2) env = typeBoth e1 e2 IntType IntType IntType ESub env
typeExp (EMul e1 e2) env = typeBoth e1 e2 IntType IntType IntType EMul env
typeExp (EDiv e1 e2) env = typeBoth e1 e2 IntType IntType IntType EDiv env

typeExp (EVar (Ident var)) env = case lookupType var env of
    Nothing -> Left $ NotDeclaredError var env
    Just tp -> Right (tp,(EVar (Ident var)))

typeExp e env = Right $ case e of
    ETrue  -> (BoolType, e)
    EFalse -> (BoolType, e)
    EInt i -> (IntType, e)
    EString str -> (StringType, EString str)
    EUnit -> (UnitType, EUnit)
    


-- SEMANTICS

eitherPair f e1 e2 = case (e1,e2) of (Right v1, Right v2) -> f v1 v2

intOp env op e1 e2 st =
    Right $ eitherPair op (compExp env e1 st) (compExp env e2 st)

unpackApply :: Operator -> TryValue -> TryValue -> TryValue
unpackApply op v1 v2 = case (v1,v2) of
    (Right v1, Right v2) -> op v1 v2
    (Left err, _) -> Left err
    (_, Left err) -> Left err

opComp :: Env -> Operator -> Exp -> Exp -> State -> TryValue
opComp env op e1 e2 st =
    unpackApply op (compExp env e1 st) (compExp env e2 st)

compExpList env exps = let
        compdL = map (compExp env) exps
        runList [] s = Right []
        runList (f:rest) s = case f s of
            Left err -> Left err
            Right v  -> case runList rest s of
                Left err -> Left err
                Right vs -> Right $ v:vs
    in runList compdL


compExp :: Env -> Exp -> State -> TryValue
compExp env (EUnit ) st = Right $ UnitVal
compExp env (ETrue ) st = Right $ BoolVal True
compExp env (EFalse) st = Right $ BoolVal False
compExp env (EInt i) st = Right $ IntVal i
compExp env (EString str) st = Right $ StringVal str

compExp env (EAdd e1 e2) st = opComp env valAdd e1 e2 st
compExp env (ESub e1 e2) st = opComp env valSub e1 e2 st
compExp env (EMul e1 e2) st = opComp env valMul e1 e2 st
compExp env (EDiv e1 e2) st = opComp env valDiv e1 e2 st

compExp env (EEq e1 e2) st = opComp env valEq e1 e2 st
compExp env (ELt e1 e2) st = opComp env valLt e1 e2 st

compExp env (EIf e1 e2 e3) st = case compExp env e1 st of
    Right (BoolVal True)  -> compExp env e2 st
    Right (BoolVal False) -> compExp env e3 st

compExp env (EVar (Ident var)) st = case lookupVarValue var env st of
    Nothing -> Left $ UninitializedException var env st
    Just v -> Right v

compExp env (ELet [] exp) st = compExp env exp st
compExp env (ELet ((FSTDec (Ident var) tpt vexp):rest) exp) st =
    case compExp env vexp st of
        Left err -> Left err
        Right val -> case lookupTypeDef env tpt of
            Right tp -> let
                    (newEnv, newSt) = createVar var tp env val st
                in compExp newEnv (ELet rest exp) newSt
compExp env (ELet ((FSAlias (Ident ntnm) tpt):rest) exp) st =
    case lookupTypeDef env tpt of
        Right tp -> compExp (addType ntnm tp env) (ELet rest exp) st
    
compExp env (ELet ((FSUnTDec (Ident var) vexp):rest) exp) st = undefined

compExp env (EFunc decls tpt exp) st =
    case lookupTypeDef env tpt of
        Right tp -> case addArguments decls env of
            Right funEnv -> case argTypes env decls of
                Right argTps -> Right $ FunVal argTps funF tp where
                    funF vals = let
                            runSt = setValues (zip (argNames decls) vals)
                                                funEnv st
                        in compExp funEnv exp runSt

compExp env (ENFunc (Ident fun) decls tpt exp) st =
    case lookupTypeDef env tpt of
        Right tp -> case argTypes env decls of
            Right argTps -> let
                    funVal = compExp funEnv (EFunc decls tpt exp) funSt where
                        funType = FuncType argTps tp
                        realVal = case funVal of Right v -> v
                        (funEnv, funSt) = createVar fun funType env realVal st
                in funVal

compExp env (Call fexp exps) st = case compExp env fexp st of
    Left err -> Left err
    Right (FunVal types cont tp) -> let
            argVals = map (\arg -> unright $ compExp env arg st) exps
        in cont argVals
            
compExp env (EMatch exp tpt prods) st = let
        expTp = fst $ unright $ typeExp exp env
        tp = unright $ lookupTypeDef env tpt
    in case compExp env exp st of
        Left err -> Left err
        Right val -> matchProds expTp env val prods st

matchProds tp env val [] st = Left CannotMatchException
matchProds tp env val (Prod pat exp:rest) st = case compPat tp env pat val st of
    Nothing -> matchProds tp env val rest st
    Just (newEnv,newSt) -> compExp newEnv exp newSt

-- compPat tp env pat val st = error $ (show tp) ++ (show pat) ++ (show val)
compPat tp env PDef val st = Just (env,st)
compPat tp env (PVar (Ident var)) val st = Just $ createVar var tp env val st
compPat (AlgType _ constrs) env (PCon (Ident cname) pats) (AlgVal (Constr pname _) vals) st =
    if pname /= cname
        then Nothing
        else case filter (\(Constr n _) -> n == cname) constrs of
                (Constr _ types):_ -> foldCompPats env (zip3 types pats vals) st


foldCompPats env [] st = Just (env,st)
foldCompPats env ((tp,pat,val):rest) st = case compPat tp env pat val st of
    Nothing -> Nothing
    Just (newEnv,newSt) -> foldCompPats newEnv rest newSt





