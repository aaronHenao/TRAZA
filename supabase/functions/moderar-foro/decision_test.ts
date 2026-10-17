// Pruebas de la decisión de la doble pasada (SCRUM-335): cada fila de la
// tabla de `decision.ts`.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { decidir, MOTIVO_SIN_RESPUESTA, type ResultadoPasada } from "./decision.ts";
import { MOTIVO_GENERICO, MOTIVO_SPAM } from "./politica_traza.ts";
import type { SenalesSpam } from "./spam.ts";

const seguro: ResultadoPasada = {
  ok: true,
  veredicto: { seguro: true, categorias: [] },
};

function inseguro(...categorias: string[]): ResultadoPasada {
  return { ok: true, veredicto: { seguro: false, categorias } };
}

const fallo: ResultadoPasada = { ok: false, error: "NVIDIA respondió 500" };

const sinSpam: SenalesSpam = { esSpam: false, senales: [] };
const conSpam: SenalesSpam = { esSpam: true, senales: ["Enlace con promoción"] };

describe("decidir", () => {
  it("aprueba lo que las dos pasadas consideran seguro (criterio 2)", () => {
    assert.deepEqual(decidir(seguro, seguro, sinSpam), {
      estado: "aprobada",
      motivo: null,
      categorias: [],
    });
  });

  it("rechaza lo ofensivo en lo que coinciden las dos pasadas (criterio 4)", () => {
    const decision = decidir(inseguro("Harassment", "Profanity"), inseguro(), sinSpam);

    assert.equal(decision.estado, "rechazada");
    assert.deepEqual(decision.categorias, [
      "Acoso o insultos",
      "Lenguaje ofensivo o vulgar",
    ]);
    assert.equal(decision.motivo, "Acoso o insultos, Lenguaje ofensivo o vulgar");
  });

  it("rechaza el spam si la política y las señales coinciden (criterio 1)", () => {
    assert.deepEqual(decidir(seguro, inseguro(), conSpam), {
      estado: "rechazada",
      motivo: MOTIVO_SPAM,
      categorias: [MOTIVO_SPAM],
    });
  });

  it("suma el spam a lo ofensivo si también lo es", () => {
    const decision = decidir(inseguro("Profanity"), inseguro(), conSpam);
    assert.deepEqual(decision.categorias, ["Lenguaje ofensivo o vulgar", MOTIVO_SPAM]);
  });

  it("rechaza con el motivo genérico si la categoría no se reconoce", () => {
    const decision = decidir(inseguro(), inseguro(), sinSpam);
    assert.equal(decision.estado, "rechazada");
    assert.deepEqual(decision.categorias, [MOTIVO_GENERICO]);
  });

  describe("deja pendiente cuando la IA tiene dudas", () => {
    it("solo la política lo marca y no hay señales de spam", () => {
      const decision = decidir(seguro, inseguro(), sinSpam);
      assert.equal(decision.estado, "pendiente");
      assert.match(decision.motivo ?? "", /no está segura/);
    });

    it("solo la taxonomía lo marca", () => {
      const decision = decidir(inseguro("Violence"), seguro, sinSpam);
      assert.equal(decision.estado, "pendiente");
      assert.deepEqual(decision.categorias, ["Contenido violento"]);
      assert.match(decision.motivo ?? "", /contenido violento/);
    });

    it("las dos pasadas lo aprueban pero parece spam", () => {
      const decision = decidir(seguro, seguro, conSpam);
      assert.equal(decision.estado, "pendiente");
      assert.match(decision.motivo ?? "", /posible spam \(Enlace con promoción\)/);
    });

    it("la taxonomía solo pide revisión (Needs Caution)", () => {
      const decision = decidir(inseguro("Needs Caution"), inseguro(), sinSpam);
      assert.equal(decision.estado, "pendiente");
    });
  });

  it("deja pendiente si alguna pasada falló, sin publicar ni rechazar", () => {
    for (const [a, b] of [[fallo, seguro], [seguro, fallo], [fallo, fallo]]) {
      assert.deepEqual(decidir(a, b, conSpam), {
        estado: "pendiente",
        motivo: MOTIVO_SIN_RESPUESTA,
        categorias: [],
      });
    }
  });
});
