{-# LANGUAGE RankNTypes,ScopedTypeVariables #-}
module HLearn.Evaluation.CrossValidation
    where

import Control.Monad
import Control.Monad.Random
import Control.Monad.ST
import Control.Monad.Trans
import Data.Array.ST
import GHC.Arr
import qualified Data.Foldable as F
import qualified Data.Map as Map
import qualified Data.Set as S
import qualified Data.Vector as V
-- import qualified Data.Vector as V

import Debug.Trace

import qualified Data.DList as D

import HLearn.Algebra
import HLearn.Algebra.History
-- import HLearn.Evaluation.Metrics
import HLearn.Models.Distributions
import HLearn.Models.Classifiers.Common
import qualified Control.ConstraintKinds as CK

-------------------------------------------------------------------------------
-- standard k-fold cross validation

type SamplingMethod = forall dp r. MonadRandom r => [dp] -> r [([dp],[dp])]

repeatExperiment :: Int -> SamplingMethod -> SamplingMethod
repeatExperiment n f xs =
    liftM concat $ forM [1..n] $ \_ -> do
        xs' <- shuffle xs
        f xs'

trainingPercent :: Double -> SamplingMethod
trainingPercent percent xs = do
    xs' <- shuffle xs
    let n = round $ percent * fromIntegral (length xs')
    return [ (take n xs', drop n xs') ]

setMaxDatapoints :: Int -> SamplingMethod -> SamplingMethod
setMaxDatapoints n f xs = do
    xs' <- shuffle xs
    f $ take n xs'

kfold :: Int -> SamplingMethod
kfold k xs = do
    xs' <- shuffle xs
    let step = floor $ (fromIntegral $ length xs :: Double) / fromIntegral k
    trace ("step="++show step) $ return 
        [ ( take ((i)*step) xs' ++ drop ((i+1)*step) xs'
          , take step $ drop (i*step) xs'
          )
        | i <- [0..k-1] 
        ]

-- leaveOneOut :: SamplingMethod 
-- leaveOneOut xs = return $ map (\x -> [x]) xs
-- 
-- withPercent :: Double -> SamplingMethod -> SamplingMethod
-- withPercent p f xs = do 
--     xs' <- shuffle xs
--     f $ take (floor $ (fromIntegral $ length xs') * p) xs'
-- 
-- repeatExperiment :: Int -> SamplingMethod -> SamplingMethod
-- repeatExperiment i f xs = do
--     liftM concat $ forM [1..i] $ \i -> do
--         f xs
-- 
-- kfold :: Int -> SamplingMethod
-- kfold k xs = do
--     xs' <- shuffle xs
--     return [takeEvery k $ drop j xs' | j<-[0..k-1]]
--     where
--         takeEvery n [] = []
--         takeEvery n xs = head xs : (takeEvery n $ drop n xs)
-- 
-- numSamples :: Int -> SamplingMethod -> SamplingMethod
-- numSamples n f dps = f $ take n dps

-- | randomly shuffles a list in time O(n log n); see http://www.haskell.org/haskellwiki/Random_shuffle
shuffle :: MonadRandom m => [a] -> m [a]
shuffle xs = do
    let l = length xs
    rands <- take l `liftM` getRandomRs (0, l-1)
    let ar = runSTArray $ do
            ar <- thawSTArray $ listArray (0, l-1) xs
            forM_ (zip [0..(l-1)] rands) $ \(i, j) -> do
                vi <- readSTArray ar i
                vj <- readSTArray ar j
                writeSTArray ar j vi
                writeSTArray ar i vj
            return ar
    return (elems ar)

---------------------------------------

type LossFunction = forall model. 
    ( Classifier model
    , HomTrainer model 
    , Labeled (Datapoint model)
    , Eq (Label (Datapoint model))
    ) => model -> [Datapoint model] -> Double

accuracy :: LossFunction 
accuracy model dataL = (fromIntegral $ length $ filter (==False) resultsL) / (fromIntegral $ length dataL)
    where
        resultsL = map (\(l1,l2) -> l1/=l2) $ zip trueL classifyL
        trueL = map getLabel dataL
        classifyL = map (classify model . getAttributes) dataL

errorRate :: LossFunction
errorRate model dataL = 1 - accuracy model dataL

---------------------------------------


validateM :: forall model g container.
    ( HomTrainer model
    , Classifier model
    , RandomGen g
    , Eq (Datapoint model)
    , Eq (Label (Datapoint model))
    , F.Foldable container
    ) => SamplingMethod 
      -> LossFunction 
      -> container (Datapoint model) 
      -> ([Datapoint model] -> History model)
      -> RandT g History (Normal Double Double)
validateM samplingMethod loss xs trainM = do
    xs' <- samplingMethod $ F.toList xs 
    lift $ collectEvents $ fmap trainNormal $ forM xs' $ \(trainingset, testset) -> do
        model <- trainM trainingset
        return $ loss model testset


