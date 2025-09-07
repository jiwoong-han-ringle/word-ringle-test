from sklearn.model_selection import GridSearchCV
from sklearn.metrics import accuracy_score, confusion_matrix, classification_report, mean_squared_error
import pickle
import sys
import nltk
from nltk.corpus import wordnet as wn
from nltk.tokenize import word_tokenize
from nltk import pos_tag
from nltk.stem import WordNetLemmatizer
from nltk.corpus import wordnet
import json
import spacy
from spacy.tokenizer import Tokenizer
import re
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn
# 글로벌 변수로 모델과 도구들 초기화 (앱 시작 시 한 번만)
nlp = None
lemmatizer = None

def initialize_models():
    """앱 시작 시 모델들을 한 번만 로딩"""
    global nlp, lemmatizer
    
    if nlp is None:
        special_cases = {":)": [{"ORTH": ":)"}]}
        simple_url_re = re.compile(r'''^https?://''')
        
        def custom_tokenizer(nlp_model):
            return Tokenizer(nlp_model.vocab, rules=special_cases,
                           url_match=simple_url_re.match)
        
        nlp = spacy.load("en_core_web_sm")  # Load the English model
        nlp.tokenizer = custom_tokenizer(nlp)
        print("✅ spaCy model loaded successfully")
    
    if lemmatizer is None:
        lemmatizer = WordNetLemmatizer()
        print("✅ NLTK lemmatizer initialized")

# 앱 시작 시 모델 초기화
initialize_models()
def getRootVerb(word, wordNetPos):
  return lemmatizer.lemmatize(word, pos=wordNetPos)
def getWordsPosFromSentence(sentence):
    # 문장을 넣어주고, 그다음에 원형으로 바꾸고..
    doc = nlp(sentence)
    token_list = []
    for token in doc:
      root = None
      
      # elif 구조로 수정하여 중복 실행 방지
      if token.pos_ == "VERB":
        root = getRootVerb(token.text, wordnet.VERB).lower()
      elif token.pos_ == "NOUN":
        root = getRootVerb(token.text, wordnet.NOUN).lower()
      elif token.pos_ == "AUX":
        root = getRootVerb(token.text, wordnet.VERB).lower()
      elif token.pos_ == "ADJ":
        root = getRootVerb(token.text, wordnet.ADJ).lower()
      elif token.pos_ == "ADV":
        root = getRootVerb(token.text, wordnet.ADV).lower()
      elif token.pos_ in ["SCONJ", "PART", "CCONJ", "DET"]:
        root = token.text.lower()
      else:
        # PRON, PROPN, NUM, PUNCT 등은 원형화 불가능하므로 None
        root = None
        
      token_dict = {"word": token.text, "pos": token.pos_, "root": root}
      token_list.append(token_dict)
    return token_list
def getDataFromNode():
    word = sys.argv[1:][0]
    return word
class SentenceRequest(BaseModel):
    sentence: str

app = FastAPI()

@app.post("/analyze")
def analyze_sentence(req: SentenceRequest):
    token_list = getWordsPosFromSentence(req.sentence)
    return token_list

if __name__ == "__main__":
    uvicorn.run("word:app", host="0.0.0.0", port=8000)
