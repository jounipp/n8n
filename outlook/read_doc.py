from docx import Document
import sys

# Aseta UTF-8 koodaus
sys.stdout.reconfigure(encoding='utf-8')

# Lue dokumentti
doc = Document("Category Discovery Analysis_dokumentaatio.docx")

# Tulosta tekstisisältö
for para in doc.paragraphs:
    text = para.text.strip()
    if text:
        print(text)
        print()