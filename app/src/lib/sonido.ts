let contexto: AudioContext | null = null;

function tono(frecuencia: number, inicio: number, duracion: number) {
  contexto ??= new AudioContext();
  if (contexto.state === 'suspended') void contexto.resume();
  const osc = contexto.createOscillator();
  const gan = contexto.createGain();
  osc.frequency.value = frecuencia;
  osc.type = 'square';
  gan.gain.value = 0.15;
  osc.connect(gan).connect(contexto.destination);
  const t = contexto.currentTime + inicio;
  osc.start(t);
  osc.stop(t + duracion);
}

export function sonidoOk() {
  tono(1200, 0, 0.09);
}

export function sonidoError() {
  tono(220, 0, 0.18);
  tono(180, 0.22, 0.28);
}
