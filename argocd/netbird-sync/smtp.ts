// Minimal SMTP client for email-oauth2-proxy (plain SMTP, AUTH PLAIN).
// Enough for one alert email per run: EHLO, AUTH, MAIL FROM, RCPT TO, DATA
// with dot-stuffing, QUIT. No TLS — the proxy is an in-cluster hop.
import { connect } from "node:net";

export interface Mail {
  host: string;
  port: number;
  user: string;
  password: string;
  /** e.g. "NetBird sync <noreply@mia.cx>" — the <> part feeds MAIL FROM. */
  from: string;
  to: string;
  subject: string;
  text: string;
}

const envelopeFrom = (from: string): string => {
  const m = from.match(/<([^>]+)>/);
  return m?.[1] ?? from;
};

export const sendMail = (mail: Mail): Promise<void> =>
  new Promise((resolve, reject) => {
    const socket = connect({ host: mail.host, port: mail.port });
    socket.setEncoding("utf8");
    socket.setTimeout(15_000);

    let buffer = "";
    // Lines arrive when the peer answers; reply code is the first 3 chars.
    const readReply = (): Promise<{ code: number; text: string }> =>
      new Promise((res, rej) => {
        const onData = (chunk: string) => {
          buffer += chunk;
          // A reply ends when the last line is a complete "NNN text" line;
          // continuation lines use "NNN-" so they can't trip this early.
          if (!/(^|\r\n)\d{3} [^\r\n]*\r\n$/.test(buffer)) return;
          const code = parseInt(buffer.slice(0, 3), 10);
          socket.off("data", onData);
          const text = buffer;
          buffer = "";
          res({ code, text });
        };
        socket.on("data", onData);
        socket.once("error", rej);
      });

    const command = async (line: string, expect: readonly number[]) => {
      socket.write(line + "\r\n");
      const { code, text } = await readReply();
      if (!expect.includes(code))
        throw new Error(
          `SMTP ${line.split(" ")[0]}: expected ${expect}, got ${code} ${text.trim()}`,
        );
    };

    const run = async () => {
      const greeting = await readReply();
      if (greeting.code !== 220)
        throw new Error(`SMTP greeting ${greeting.code}`);
      await command(`EHLO ${mail.host}`, [250]);
      const auth = Buffer.from(`\0${mail.user}\0${mail.password}`).toString(
        "base64",
      );
      await command(`AUTH PLAIN ${auth}`, [235]);
      await command(`MAIL FROM:<${envelopeFrom(mail.from)}>`, [250]);
      await command(`RCPT TO:<${mail.to}>`, [250, 251]);
      await command("DATA", [354]);
      const headers = [
        `From: ${mail.from}`,
        `To: ${mail.to}`,
        `Subject: ${mail.subject}`,
        "Content-Type: text/plain; charset=utf-8",
      ];
      const body = mail.text
        .split("\n")
        .map((l) => (l.startsWith(".") ? `.${l}` : l))
        .join("\r\n");
      await command([...headers, "", body, "."].join("\r\n"), [250]);
      await command("QUIT", [221]);
    };

    socket.once("timeout", () => reject(new Error("SMTP timeout")));
    socket.once("error", reject);
    socket.once("connect", () => {
      run()
        .then(() => {
          socket.end();
          resolve();
        })
        .catch((err) => {
          socket.destroy();
          reject(err);
        });
    });
  });
