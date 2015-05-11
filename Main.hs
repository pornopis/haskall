module Main where

import System.Environment

import LexHaskall
import ParHaskall
import SkelHaskall
import PrintHaskall
import AbsHaskall
import ErrM

import Expressions
import Environment
import Instructions

import Data.Map (empty)

parseIt input = case pProgram $ myLexer input of
    Bad err -> err
    Ok prog -> case prog of
        Eval exp -> case compileExpression exp emptyEnv of
            Right v -> show (v emptyState)
            Left er -> show er
        Prog stm -> "dupa"--case evalStm emptyEnv stm emptyState of
            --Right s -> show s
            --Left er -> show er

main :: IO ()
main = do
    args <- getArgs
    input <- case args of
        [] -> getContents
        f:_ -> readFile f
    putStrLn $ parseIt input
    return ()
