from fastapi import FastAPI

app = FastAPI(title="Gameday Pick'em API")

@app.get("/health")

def health():
    return {"status": "ok"}