FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && python -m spacy download en_core_web_sm \
    && python -c "import nltk; nltk.download('wordnet'); nltk.download('averaged_perceptron_tagger')"

COPY word.py ./

EXPOSE 8000

CMD ["uvicorn", "word:app", "--host", "0.0.0.0", "--port", "8000"]

