// Pruebas de las señales de spam (SCRUM-335).
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { normalizarTexto, senalesDeSpam } from "./spam.ts";

describe("senalesDeSpam", () => {
  it("no marca una pregunta normal de running", () => {
    const resultado = senalesDeSpam(
      "¿Qué tenis me recomiendan para mi primera media maratón? Corro a 6:10/km.",
    );
    assert.deepEqual(resultado, { esSpam: false, senales: [] });
  });

  it("no marca el anuncio de una carrera con su enlace de inscripción", () => {
    const resultado = senalesDeSpam(
      "El domingo es la 10K de Medellín, las inscripciones están en https://carrera10k.co",
    );
    assert.equal(resultado.esSpam, false);
  });

  it("marca un enlace con promoción", () => {
    const resultado = senalesDeSpam(
      "Descuento del 50% en suplementos, compra aquí: www.suplementos-baratos.shop",
    );
    assert.equal(resultado.esSpam, true);
    assert.ok(resultado.senales.includes("Enlace con promoción"));
  });

  it("marca un teléfono con promoción", () => {
    const resultado = senalesDeSpam(
      "Gana dinero desde tu casa, escríbeme al WhatsApp 300 123 4567",
    );
    assert.equal(resultado.esSpam, true);
    assert.ok(resultado.senales.includes("Teléfono con promoción"));
  });

  it("marca varios enlaces", () => {
    const resultado = senalesDeSpam("mira https://a.com y https://b.com");
    assert.ok(resultado.senales.includes("2 enlaces"));
  });

  it("marca el texto repetitivo", () => {
    assert.equal(senalesDeSpam("corran corran corran corran corran").esSpam, true);
    assert.equal(senalesDeSpam("holaaaaaaaaaaaaaa").esSpam, true);
  });

  it("marca repetir lo que el autor ya publicó", () => {
    const resultado = senalesDeSpam(
      "Únanse a mi grupo de running de los domingos",
      ["  únanse a mi GRUPO de running de los  domingos "],
    );
    assert.deepEqual(resultado.senales, ["Repite un texto que ya publicó"]);
  });

  it("no marca repetir un comentario corto", () => {
    assert.equal(senalesDeSpam("¡Gracias!", ["¡Gracias!"]).esSpam, false);
  });
});

describe("normalizarTexto", () => {
  it("quita tildes, mayúsculas y espacios de más", () => {
    assert.equal(normalizarTexto("  Él  CORRIÓ   rápido "), "el corrio rapido");
  });
});
