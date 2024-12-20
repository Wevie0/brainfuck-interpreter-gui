
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
-- |Module: GUITest
module GUITest where

import Control.Concurrent (forkIO, killThread, newEmptyMVar, putMVar, tryTakeMVar)
import Control.Monad (unless, void, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (MonadIO (liftIO), ReaderT (runReaderT))
import Data.Binary (Word8)
import Data.GI.Base (AttrOp ((:=)), new, on, set)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import qualified Data.Text as T
import qualified GI.Gdk as Gdk
import qualified GI.GLib as GLib
import qualified GI.Gtk as Gtk
import InterpreterGui (EvalState (..), GUIState (..), run)
import Tape (Tape (..), index, shiftLeft, shiftRight, store)
import TapeGUI (drawTape)

activate :: Gtk.Application -> IO ()
activate app = do

  ------------------------------------ TURING SIM STUFF --------------------------------------
  simVbox      <- new Gtk.Box  [ #orientation := Gtk.OrientationVertical, #spacing := 10 ]
  simGrid      <- new Gtk.Grid [ #columnSpacing := 10 ]
  simButtonBox <- new Gtk.Box  [ #orientation := Gtk.OrientationHorizontal, #spacing := 10 ]
  (leftButton, lockedLeftButton) <- createButton "Left" True
  (rightButton, lockedRightButton) <- createButton "Right" True

  set simGrid [#halign := Gtk.AlignCenter]
  #packStart simButtonBox lockedLeftButton True True 0
  #packStart simButtonBox lockedRightButton True True 0
  #packStart simVbox simGrid True False 0
  #packStart simVbox simButtonBox False False 0
  let initialTape = Tape (repeat 0) 0 (repeat 0) :: Tape Word8
  tapeRef <- newIORef initialTape
  offsetRef <- newIORef 0
  drawTape simGrid tapeRef offsetRef

  on leftButton #clicked $ do
    modifyIORef' offsetRef pred
    drawTape simGrid tapeRef offsetRef

  on rightButton #clicked $ do
    modifyIORef' offsetRef succ
    drawTape simGrid tapeRef offsetRef

  --------------------------------------------------------------------------------------------

  -- run and reset buttons
  (button, lockedButton)           <- createButton "Run" True
  (resetButton, lockedResetButton) <- createButton "Reset" False
  (stepButton, lockedStepButton)   <- createButton "Step" True
  (nextButton, lockedNextButton)   <- createButton "Next" False

  -- bottom half of the console that works with the "," command
  (sendButton, lockedSendButton)   <- createButton "Send" False
  inputEntry <- new Gtk.Entry [ #sensitive := False ]
  inputBox   <- new Gtk.Box [ #orientation := Gtk.OrientationHorizontal ]
  #packStart inputBox inputEntry True True 0
  #packStart inputBox lockedSendButton False False 0

  -- adding the brainfuck text entry box and the pseudo-cout box
  entry      <- new Gtk.TextView []
  outputView <- new Gtk.TextView []
  Gtk.textViewSetEditable outputView False
  scrolledWindowEntry  <- new Gtk.ScrolledWindow []
  #setPolicy scrolledWindowEntry Gtk.PolicyTypeAlways Gtk.PolicyTypeAutomatic
  #add scrolledWindowEntry entry
  scrolledWindowOutput <- new Gtk.ScrolledWindow []
  #setPolicy scrolledWindowOutput Gtk.PolicyTypeAlways Gtk.PolicyTypeAutomatic
  #add scrolledWindowOutput outputView
  #setSizeRequest scrolledWindowEntry 256 128
  #setSizeRequest scrolledWindowOutput 256 128

  buffer   <- #getBuffer entry
  tagTable <- #getTagTable buffer

  commentTag <- createTag "#6c6f85" tagTable
  plusTag    <- createTag "#dc8a78" tagTable
  minusTag   <- createTag "#dc8a78" tagTable
  rAngleTag  <- createTag "#7287fd" tagTable
  lAngleTag  <- createTag "#7287fd" tagTable
  periodTag  <- createTag "#8839ef" tagTable
  commaTag   <- createTag "#8839ef" tagTable
  errorTag   <- createTag "#d20f39" tagTable

  bracketTags <- mapM (\colour -> do
    tag <- Gtk.textTagNew Nothing
    _   <- #add tagTable tag
    set tag [#foreground := colour]
    return tag) ["#df8e1d", "#40a02b", "#04a5e5", "#7287fd"]

  on buffer #changed $ do
    startIter <- #getStartIter buffer
    endIter   <- #getEndIter buffer
    #removeAllTags buffer startIter endIter
    #applyTag buffer commentTag startIter endIter

    findCharAndApplyTag buffer (T.pack "+") plusTag
    findCharAndApplyTag buffer (T.pack "-") minusTag
    findCharAndApplyTag buffer (T.pack ">") rAngleTag
    findCharAndApplyTag buffer (T.pack "<") lAngleTag
    findCharAndApplyTag buffer (T.pack ".") periodTag
    findCharAndApplyTag buffer (T.pack ",") commaTag

    matchBrackets buffer errorTag bracketTags

  stepperLock <- newEmptyMVar
  interpreterThreadRef <- newIORef Nothing

  -- starting interpreter when run button is clicked
  on button #clicked $ do
    set button [#sensitive := False]
    set resetButton [#sensitive := True]
    buffer       <- #getBuffer entry
    startIter    <- #getStartIter buffer
    endIter      <- #getEndIter buffer
    text         <- #getText buffer startIter endIter False
    outputBuffer <- #getBuffer outputView
    Gtk.textBufferSetText outputBuffer "" (-1)
    threadId <- liftIO $ forkIO $ void $
      runReaderT (InterpreterGui.run (T.unpack text))
        GUIState { outputView  = outputView
                 , inputField  = inputEntry
                 , inputToggle = sendButton
                 , evalState   = RunMode
                 , stepperLock = stepperLock
                 , tapeRef     = tapeRef
                 , tapeGrid    = simGrid
                 , nextButton  = nextButton
                 , offsetRef   = offsetRef }
    liftIO $ writeIORef interpreterThreadRef (Just threadId)
    return ()

  -- reset clears the output view, unlocks run, and locks itself
  on resetButton #clicked $ do
    set button      [#sensitive := True]
    set stepButton  [#sensitive := True]
    set resetButton [#sensitive := False]
    set nextButton  [#sensitive := False]
    outputBuffer <- #getBuffer outputView
    liftIO $ void $ tryTakeMVar stepperLock
    Gtk.textBufferSetText outputBuffer "" (-1)
    writeIORef tapeRef initialTape
    writeIORef offsetRef 0
    drawTape simGrid tapeRef offsetRef
    maybeThreadId <- readIORef interpreterThreadRef
    case maybeThreadId of
      Just threadId -> do
        liftIO $ killThread threadId
        liftIO $ writeIORef interpreterThreadRef Nothing
      Nothing -> return ()


  on stepButton #clicked $ do
    set button      [#sensitive := False]
    set stepButton  [#sensitive := False]
    set resetButton [#sensitive := True]
    set nextButton  [#sensitive := True]
    buffer       <- #getBuffer entry
    startIter    <- #getStartIter buffer
    endIter      <- #getEndIter buffer
    text         <- #getText buffer startIter endIter False
    outputBuffer <- #getBuffer outputView
    Gtk.textBufferSetText outputBuffer "" (-1)
    threadId <- liftIO $ forkIO $ void $
      runReaderT (InterpreterGui.run (T.unpack text))
        GUIState { outputView  = outputView
                 , inputField  = inputEntry
                 , inputToggle = sendButton
                 , evalState   = StepMode
                 , stepperLock = stepperLock
                 , tapeRef     = tapeRef
                 , tapeGrid    = simGrid
                 , nextButton  = nextButton
                 , offsetRef   = offsetRef }
    liftIO $ writeIORef interpreterThreadRef (Just threadId)
    return ()

  on nextButton #clicked $ do
    liftIO $ putMVar stepperLock ()

  -- GUI margins
  #setMarginTop scrolledWindowEntry 32
  #setMarginBottom scrolledWindowEntry 32
  #setMarginTop button 32
  #setMarginBottom button 32
  #setMarginTop resetButton 32
  #setMarginBottom resetButton 32

  -- adding all the elements to boxes for shape and bounding
  hbox      <- new Gtk.Box [ #orientation := Gtk.OrientationHorizontal ]
  vbox      <- new Gtk.Box [ #orientation := Gtk.OrientationVertical ]
  buttonBox <- new Gtk.Box [ #orientation := Gtk.OrientationHorizontal ]
  terminal  <- new Gtk.Box [ #orientation := Gtk.OrientationVertical ]
  set buttonBox [#halign := Gtk.AlignCenter]
  #packStart hbox scrolledWindowEntry True True 32
  #packStart terminal scrolledWindowOutput True True 0
  #packStart terminal inputBox False False 0
  #setSizeRequest inputBox (-1) 32
  #packStart vbox terminal True True 32
  #packStart vbox simVbox True True 32
  #packStart buttonBox lockedButton False False 16
  #packStart buttonBox lockedStepButton False False 16
  #packStart buttonBox lockedNextButton False False 16
  #packStart buttonBox lockedResetButton False False 16
  #packStart vbox buttonBox True True 32
  #packStart hbox vbox True True 32

  -- adding bounding box to main window
  window <- new Gtk.ApplicationWindow
    [ #application := app
    , #title := "Brainfuck Integrated Development Environment" ]
  #add window hbox

  #showAll window

findCharAndApplyTag :: Gtk.TextBuffer -> T.Text -> Gtk.TextTag -> IO ()
findCharAndApplyTag buffer char tag = do
    startIter <- #getStartIter buffer
    let findAndTag iter = do
          (found, matchStart, matchEnd) <- #forwardSearch iter char [Gtk.TextSearchFlagsVisibleOnly] Nothing
          when found $ do
            #applyTag buffer tag matchStart matchEnd
            -- continue searching from the end of the match
            findAndTag matchEnd
    findAndTag startIter

-- highlight matching pairs of brackets, red if unpaired
matchBrackets :: Gtk.TextBuffer -> Gtk.TextTag -> [Gtk.TextTag] -> IO ()
matchBrackets buffer errorTag bracketTags = do
  iter <- Gtk.textBufferGetStartIter buffer
  let loop currentIter stack i = do
    -- check if we are at the end
        isEnd <- Gtk.textIterIsEnd currentIter
        unless isEnd $ do
          char <- Gtk.textIterGetChar currentIter
          -- update the stack
          stack' <- case char of
            '[' -> do
              copiedIter1 <- Gtk.textIterCopy currentIter
              copiedIter2 <- Gtk.textIterCopy currentIter
              _ <- Gtk.textIterForwardChar copiedIter2
              #applyTag buffer errorTag currentIter copiedIter2
              return (copiedIter1 : stack)
            ']' -> do
              case stack of
                (lastIter:rest) -> do
                  let bracketTag = bracketTags !! i

                  copiedIter <- Gtk.textIterCopy lastIter
                  _ <- Gtk.textIterForwardChar copiedIter
                  #applyTag buffer bracketTag lastIter copiedIter

                  copiedIter <- Gtk.textIterCopy currentIter
                  _ <- Gtk.textIterForwardChar copiedIter
                  #applyTag buffer bracketTag currentIter copiedIter

                  return rest
                [] -> do
                  -- too many ]
                  copiedIter <- Gtk.textIterCopy currentIter
                  _ <- Gtk.textIterForwardChar copiedIter
                  #applyTag buffer errorTag currentIter copiedIter
                  return stack
            _ -> return stack
          -- traverse the text
          moved <- Gtk.textIterForwardChar currentIter
          when moved $ loop currentIter stack' (mod (i + 1) (length bracketTags))
  -- Start the search loop
  loop iter [] 0

createButton :: MonadIO m => T.Text -> Bool -> m (Gtk.Button, Gtk.AspectFrame)
createButton label status = do
  button <- new Gtk.Button [ #label     := label
                           , #sensitive := status ]
  lockedButton <- new Gtk.AspectFrame []
  set lockedButton [ #ratio      := 2.0
                   , #obeyChild  := True
                   , #shadowType := Gtk.ShadowTypeNone ]
  #add lockedButton button
  return (button, lockedButton)

createTag :: MonadIO m => T.Text -> Gtk.TextTagTable -> m Gtk.TextTag
createTag code tagTable = do
  tag <- Gtk.textTagNew Nothing
  _   <- #add tagTable tag
  set tag [ #foreground := code ]
  return tag


run :: IO ()
run = do
  maybeApp <- Gtk.applicationNew (Just "foss.brainfuck-ide") []

  case maybeApp of
    Nothing  -> putStrLn "Failed to create the GTK application."
    Just app -> do
      on app #activate (activate app)
      void $ #run app Nothing
