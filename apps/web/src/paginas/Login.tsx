// Eskemia · Ingreso (provisorio hasta las páginas públicas de la Etapa 4).
import { useState } from 'react';
import { AlertTriangle } from 'lucide-react';
import { ingresar } from '@eskemia/cliente-api';

export function Login() {
  const [email, setEmail] = useState('');
  const [clave, setClave] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  return (
    <div className="pantalla">
      <header className="encabezado">
        <span className="marca">Eskemia</span>
      </header>
      <form
        className="contenido estrecho"
        onSubmit={async (e) => {
          e.preventDefault();
          setEnviando(true);
          setError(null);
          const fallo = await ingresar(email, clave).then(
            () => false,
            () => true,
          );
          setEnviando(false);
          if (fallo) {
            setError(
              navigator.onLine
                ? 'Email o contraseña incorrectos.'
                : 'Para iniciar sesión hace falta conexión.',
            );
          }
        }}
      >
        <h1>Ingresá para recibir mercadería</h1>
        <label className="grupo">
          <span className="label">Email</span>
          <input
            className="campo"
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </label>
        <label className="grupo">
          <span className="label">Contraseña</span>
          <input
            className="campo"
            type="password"
            autoComplete="current-password"
            required
            value={clave}
            onChange={(e) => setClave(e.target.value)}
          />
        </label>
        {error && (
          <p className="aviso-error" role="alert">
            <AlertTriangle size={20} /> {error}
          </p>
        )}
        <button className="btn btn-primario" type="submit" disabled={enviando}>
          {enviando ? 'Ingresando…' : 'Ingresar'}
        </button>
      </form>
    </div>
  );
}
