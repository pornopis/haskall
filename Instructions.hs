module Instructions where
import AbsHaskall
import Expressions
import PrintHaskall
import Environment


data CompileError =
    TypeCompileError TypingError
    | VarNotDeclared String Env
    | BadAssignment String VType Exp VType
    | BadPrAssignment String VType String VType
    | BadLoopCondition Exp VType
    | CannotPrintError Exp VType
    | UndefinedProcError String Env
    | ProcArgTypesError String [VType] [VType]
    | TypeAlreadyDeclaredError String

instance Show CompileError where
    show (TypeCompileError err) = (show err)
    show (VarNotDeclared name env) = "compile error: variable " ++ name ++ 
        " is not defined in env:\n" ++ (show env)
    show (BadAssignment var tp exp expTp) = "compile error: cannot assign " ++
        "value of expression " ++ (printTree exp) ++ " of type " ++ (show tp)
        ++ " to variable " ++ var ++ " of type " ++ (show tp)
    show (BadLoopCondition exp tp) = "expression " ++ (printTree exp) ++
        " of type " ++ (show tp) ++ " cannot be a condition"
    show (CannotPrintError exp tp) = "compile error: cannot print expression "
        ++ (printTree exp) ++ " of type " ++ (show tp)
    show (UndefinedProcError pr env) = "compile error: cannot call undefined "
        ++ "procedure " ++ pr ++ " in env:\n" ++ (show env)
    show (ProcArgTypesError pr expTps actTps) = "compile error: cannot " ++
        "apply arguments of types " ++ (show actTps) ++ " to procedure " ++
        pr ++ " expecting types " ++ (show expTps)
    show (TypeAlreadyDeclaredError tp) = "compile error: type " ++ tp ++ "is "
        ++ "already declared"
    show (BadPrAssignment var varTp id pRetType) = "compile error: cannot " ++
        "assign value of procedure " ++ id ++ " of type " ++ (show pRetType) ++
        " to variable " ++ var ++ " of type " ++ (show varTp)

compileProgram pr env = compSt env pr

sequenceProgs :: Prog -> Prog -> Prog
sequenceProgs pr1 pr2 = \s -> do
    s1 <- pr1 s
    case s1 of
        Left err -> return $ Left err
        Right s2 -> pr2 s2

evalStmList :: Env -> [Stm] -> Either CompileError (Env,Prog)
evalStmList env [] = Right (env,\s -> return $ Right s)
evalStmList env (stm:stmRest) = case compSt env stm of
    Left err -> Left err
    Right (newEnv, pr) -> case evalStmList newEnv stmRest of
        Left err -> Left err
        Right (fEnv, fPr) -> Right (fEnv, sequenceProgs pr fPr)

compSt :: Env -> Stm -> Either CompileError (Env,Prog)
compSt env SPass = Right (env, \s -> return $ Right s)
compSt env (SBlock stmts) = evalStmList env stmts
-- debug
compSt env STrace = Right (env, \s -> do
    putStrLn (show env)
    putStrLn (show s)
    return $ Right s)
compSt env (STPrint exp) = case typeExp exp env of
    Left err -> Left $ TypeCompileError err
    Right (expTp, tpExp) -> case expTp of
        StringType -> Right (env, \s -> case compExp env tpExp s of
                        Left err -> return $ Left err
                        Right (StringVal str) -> do
                            putStr str
                            return $ Right s)
        IntType    -> Right (env, \s -> case compExp env tpExp s of
                        Left err -> return $ Left err
                        Right (IntVal int) -> do
                            putStr $ show int
                            return $ Right s)
        _ -> Left $ CannotPrintError tpExp expTp

compSt env (STDecl (Ident var) tpTok exp) =
    case lookupTypeDef env tpTok of
        Left err -> Left $ TypeCompileError err
        Right tp -> case expectType tp exp env of
            Left err -> Left $ TypeCompileError err
            Right (expTp, tpExp) -> let
                    (loc,newEnv) = addToEnv var expTp env
                in Right (newEnv, \s -> return $ case compExp env tpExp s of
                    Left err -> Left err
                    Right v -> Right $ addToStore v loc s)

compSt env (SUnTDecl (Ident var) exp) =
    case typeExp exp env of
        Left err -> Left $ TypeCompileError err
        Right (expTp, tpExp) -> let
                (loc,newEnv) = addToEnv var expTp env
            in Right (newEnv, \s -> return $ case compExp env tpExp s of
                Left err -> Left err
                Right v -> Right $ addToStore v loc s)

compSt env (SAssign (Ident var) exp) = case typeExp exp env of
    Left err -> Left $ TypeCompileError err
    Right (expTp, tpExp) -> case lookupEnv var env of
        Nothing -> Left $ VarNotDeclared var env
        Just (loc, tp) -> if tp /= expTp
            then Left $ BadAssignment var tp exp expTp
            else Right $ (env, \s -> return $ case compExp env tpExp s of
                Left err -> Left err
                Right v -> Right $ setInStore v loc s)

compSt env (SIf exp stms1 stms2) = case typeExp exp env of
    Left err -> Left $ TypeCompileError err
    Right (expTp, tpExp) -> if expTp /= BoolType
        then Left $ BadLoopCondition exp expTp
        else case (evalStmList env stms1, evalStmList env stms2) of
            (Left err,_) -> Left err
            (_,Left err) -> Left err
            (Right (_,pr1), Right (_,pr2)) ->
                    Right (env, \s -> case compExp env tpExp s of
                        Left err -> return $ Left err
                        Right (BoolVal True ) -> pr1 s
                        Right (BoolVal False) -> pr2 s)

compSt env (STAlias (Ident ntpt) tpt) =
    case lookupTypeDef env tpt of
        Left err -> Left $ TypeCompileError err
        Right tp -> Right (addType ntpt tp env, \s -> return $ Right s)

compSt env (SWhile exp stms) = case typeExp exp env of
    Left err -> Left $ TypeCompileError err
    Right (expTp, tpExp) -> if expTp /= BoolType
        then Left $ BadLoopCondition exp expTp
        else case evalStmList env stms of
            Left err -> Left err
            Right (_, pr) -> let
                    loop s = case compExp env tpExp s of
                        Left err -> return $ Left err
                        Right (BoolVal False) -> return  $ Right s
                        Right (BoolVal True ) -> sequenceProgs pr loop s
                in Right (env, loop)

compSt env (SProcDecl (Ident id) argts stm exp) =
    case argTypes env argts of
        Left err -> Left $ TypeCompileError err
        Right tps -> case addArguments argts env of
            Left err -> Left $ TypeCompileError err
            Right procEnv -> case compSt procEnv stm of
                Left err -> Left err
                Right (retEnv,cont) -> case typeExp exp env of
                    Left err -> Left $ TypeCompileError err
                    Right (expTp, tpExp) -> let -- case compExp env tpExp of
                            proc = Proc tps (argNames argts) cont (compExp retEnv tpExp) procEnv expTp
                        in Right (addProc id proc env, \s -> return $ Right s)

compSt env (SProcRun (Ident id) exps) = case typeExpList exps env of
    Left err -> Left $ TypeCompileError err
    Right tps -> let (argTypes,tpArgs) = unzip tps in
        case lookupProc id env of
            Nothing -> Left $ UndefinedProcError id env
            Just proc -> if (pArgTypes proc) /= argTypes
                then Left $ ProcArgTypesError id (pArgTypes proc) argTypes
                else Right (env, \s -> case compExpList env exps s of
                    Left err -> return $ Left err
                    Right vals -> let
                            newSt = setValues (zip (pArgNames proc) vals) (pEnv proc) emptyState
                            runSt = StackedState newSt s
                        in do
                            s1 <- pCont proc runSt
                            case s1 of
                                Left err -> return $ Left err
                                Right (StackedState top bot) -> return $ Right bot )

compSt env (SPrAssign (Ident var) (Ident id) exps) = case lookupEnv var env of
    Nothing -> Left $ VarNotDeclared var env
    Just (loc, varTp) -> case typeExpList exps env of
        Left err -> Left $ TypeCompileError err
        Right tps -> let (argTypes,tpArgs) = unzip tps in
            case lookupProc id env of
                Nothing -> Left $ UndefinedProcError id env
                Just proc -> if (pArgTypes proc) /= argTypes
                    then Left $ ProcArgTypesError id (pArgTypes proc) argTypes
                    else if (pRetType proc) /= varTp
                        then Left $ BadPrAssignment var varTp id (pRetType proc)
                        else Right (env, \s -> case compExpList env exps s of
                            Left err -> return $ Left err
                            Right vals -> let
                                    newSt = setValues (zip (pArgNames proc) vals) (pEnv proc) emptyState
                                    runSt = StackedState newSt s
                                in do
                                    s1 <- pCont proc runSt
                                    return $ case s1 of
                                        Left err -> Left err
                                        Right (StackedState top bot) ->
                                            case pRet proc (StackedState top bot) of
                                                Left err -> Left err
                                                Right v -> Right $ setInStore v loc bot)    

compSt env (STDef (Ident tpName) cons) =
    case lookupTypeDef env (TType (Ident tpName)) of
        Right _ -> Left $ TypeAlreadyDeclaredError tpName
        Left _ -> case produceConstrs env cons of
            Left err -> Left $ TypeCompileError err
            Right constrs -> let
                    tp = AlgType tpName constrs
                    consFuns = map (constrToFun tp) constrs
                    consNames = map (\(Constr n _) -> n) constrs
                    consTypes = map(\(Constr _ tps) -> FuncType tps tp) constrs
                    envWithT = addType tpName tp env
                    envWithC = createEmptyVars (zip consNames consTypes) envWithT
                in Right (envWithC, \s ->
                    return $ Right $ setValues (zip consNames consFuns) envWithC s)

--------------------------------------------------------

produceTypeList env [] = Right []
produceTypeList env (tpt:rest) = case lookupTypeDef env tpt of
    Left err -> Left err
    Right tp -> case produceTypeList env rest of
        Left err -> Left err
        Right tps -> Right $ tp:tps

produceConstr env (TConstr (Ident name) types) =
    case produceTypeList env types of
        Left err -> Left err
        Right tps -> Right $ Constr name tps

produceConstrs env [] = Right []
produceConstrs env (c:rest) =
    case produceConstr env c of
        Left err -> Left err
        Right cn -> case produceConstrs env rest of
            Left err -> Left err
            Right cns -> Right $ cn : cns 

