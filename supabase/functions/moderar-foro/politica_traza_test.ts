// Pruebas de las normas y los motivos (SCRUM-334). Corren igual con
// `node --test` y con `deno test`: solo usan `node:test` y `node:assert`.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  esCategoriaDeDuda,
  MOTIVO_GENERICO,
  motivoDeCategoria,
  motivosDeCategorias,
  POLITICA_TRAZA,
} from "./politica_traza.ts";

describe("motivoDeCategoria", () => {
  it("traduce las categorías de la taxonomía al español", () => {
    assert.equal(motivoDeCategoria("Harassment"), "Acoso o insultos");
    assert.equal(
      motivoDeCategoria("Hate/Identity Hate"),
      "Lenguaje discriminatorio o de odio",
    );
    assert.equal(motivoDeCategoria("Profanity"), "Lenguaje ofensivo o vulgar");
    assert.equal(motivoDeCategoria("Fraud/Deception"), "Fraude o engaño");
  });

  it("reconoce la categoría aunque cambie cómo se escribe", () => {
    assert.equal(motivoDeCategoria("Guns and Illegal Weapons"), "Armas");
    assert.equal(motivoDeCategoria("guns/illegal weapons"), "Armas");
    assert.equal(
      motivoDeCategoria(" Suicide and Self Harm "),
      "Contenido sobre autolesiones",
    );
  });

  it("no confunde lo sexual con menores con lo sexual a secas", () => {
    assert.equal(
      motivoDeCategoria("Sexual (minor)"),
      "Contenido sexual con menores",
    );
    assert.equal(motivoDeCategoria("Sexual"), "Contenido sexual");
  });

  it("reconoce el spam que nombra la política de TRAZA", () => {
    assert.equal(motivoDeCategoria("Spam"), "Spam");
  });

  it("usa el motivo genérico si no la reconoce", () => {
    assert.equal(motivoDeCategoria("Other"), MOTIVO_GENERICO);
    assert.equal(motivoDeCategoria("Algo nuevo"), MOTIVO_GENERICO);
  });
});

describe("motivosDeCategorias", () => {
  it("no repite motivos y conserva el orden", () => {
    assert.deepEqual(
      motivosDeCategorias(["Profanity", "Harassment", "profanity"]),
      ["Lenguaje ofensivo o vulgar", "Acoso o insultos"],
    );
  });

  it("no cuenta la categoría de duda como infracción", () => {
    assert.deepEqual(motivosDeCategorias(["Needs Caution"]), []);
    assert.ok(esCategoriaDeDuda("Needs Caution"));
    assert.ok(!esCategoriaDeDuda("Harassment"));
  });
});

describe("POLITICA_TRAZA", () => {
  it("prohíbe el spam y permite el español coloquial", () => {
    assert.match(POLITICA_TRAZA, /Disallowed Behaviors:[\s\S]*Spam/);
    assert.match(POLITICA_TRAZA, /Allowed Behaviors:[\s\S]*Colloquial/);
  });

  it("prohíbe las groserías aunque no vayan dirigidas a nadie", () => {
    assert.match(
      POLITICA_TRAZA,
      /Disallowed Behaviors:[\s\S]*Profanity[\s\S]*not directed at anyone[\s\S]*Allowed Behaviors:/,
    );
  });
});
