{-# LANGUAGE DataKinds #-}

module HLearn.Models.Classifiers.Common
    where

import Control.DeepSeq
import Data.Typeable

import HLearn.Algebra
import HLearn.Algebra.LinearAlgebra
import HLearn.Models.Distributions

-------------------------------------------------------------------------------
-- Labeled datapoints


class 
    ( Scalar (Attributes dp) ~ Scalar dp
    , IsScalar (Scalar dp)
    ) => Labeled dp 
        where

    type Label dp
    type Attributes dp
    
    getLabel :: dp -> Label dp
    getAttributes :: dp -> Attributes dp

---------------------------------------

-- instance Labeled (label,attr) where
--     type Label (label,attr) = label
--     type Attributes (label,attr) = attr
--     
--     getLabel = fst
--     getAttributes = snd

---------------------------------------

data MaybeLabeled label attr = MaybeLabeled
    { label :: Maybe label
    , attr :: attr
    }
    deriving (Read,Show,Typeable)

instance Eq attr => Eq (MaybeLabeled label attr) where
    a==b = attr a==attr b

instance Ord attr => Ord (MaybeLabeled label attr) where
    a `compare` b = attr a `compare` attr b

instance (NFData label, NFData attr) => NFData (MaybeLabeled label attr) where
    rnf (MaybeLabeled label attr) = deepseq label $ rnf attr

noLabel :: attr -> MaybeLabeled label attr
noLabel attr = MaybeLabeled
    { label = Nothing
    , attr = attr
    }

instance 
    ( IsScalar (Scalar attr)
    ) => Labeled (MaybeLabeled label attr) 
        where

    type Label (MaybeLabeled label attr) = Maybe label
    type Attributes (MaybeLabeled label attr) = attr

    getLabel = label
    getAttributes = attr

type instance Scalar (MaybeLabeled label attr) = Scalar attr


instance ValidTensor1 dp => ValidTensor1 (MaybeLabeled l dp) where
    type Tensor 0 (MaybeLabeled l dp) = Tensor 0 dp
    type Tensor 1 (MaybeLabeled l dp) = Tensor 1 dp
    type Tensor 2 (MaybeLabeled l dp) = Tensor 2 dp

instance MetricSpace attr => MetricSpace (MaybeLabeled label attr) where
    distance (MaybeLabeled _ a1) (MaybeLabeled _ a2) = distance a1 a2
--     isFartherThan dp1 dp2 = isFartherThan (getAttributes dp1) (getAttributes dp2)
--     isFartherThanWithDistance dp1 dp2 = isFartherThanWithDistance (getAttributes dp1) (getAttributes dp2)

-------------------------------------------------------------------------------
-- Classification

class 
    ( Labeled (Datapoint model)
    ) => ProbabilityClassifier model 
        where
    type ResultDistribution model    
    probabilityClassify :: model -> Attributes (Datapoint model) -> ResultDistribution model
    
class MarginClassifier model where
    margin :: model -> Attributes (Datapoint model) -> (Scalar model, Label (Datapoint model))
    
class 
    ( Labeled (Datapoint model)
    ) => Classifier model
        where
    classify :: model -> Attributes (Datapoint model) -> Label (Datapoint model)

-- | this is a default instance that any instance of Classifier should satisfy if it is also an instance of ProbabilityClassifier
-- instance 
--     ( Label (Datapoint model) ~ Datapoint (ResultDistribution model)
--     , Mean (ResultDistribution model)
--     , ProbabilityClassifier model
--     ) => Classifier model
--         where
--     classify model dp = mean $ probabilityClassify model dp

-------------------------------------------------------------------------------
-- Regression

-- | Regression is classification where the class labels are (isomorphic to) real numbers.  The constraints could probably be better specified, but they're close enough for now.
class (Classifier model, Scalar model ~ Label (Datapoint model)) => Regression model
instance (Classifier model, Scalar model ~ Label (Datapoint model)) => Regression model
