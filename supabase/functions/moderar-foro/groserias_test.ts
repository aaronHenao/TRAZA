// Pruebas de la lista de groserías (SCRUM-322).
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { buscarGroserias, normalizarParaGroserias } from "./groserias.ts";

describe("buscarGroserias", () => {
  describe("marca las inequívocas", () => {
    it("un malparido suelto, que la IA dejó pasar", () => {
      assert.deepEqual(buscarGroserias("malparido").inequivocas, ["malparido"]);
    });

    it("dentro de una frase, con mayúsculas y signos", () => {
      const { inequivocas } = buscarGroserias(
        "¡Qué ruta tan MALPARIDA! Casi no la termino.",
      );
      assert.deepEqual(inequivocas, ["malparida"]);
    });

    it("en plural", () => {
      assert.deepEqual(buscarGroserias("esos malparidos").inequivocas, [
        "malparido",
      ]);
    });

    it("disimulada con números o letras repetidas", () => {
      assert.deepEqual(buscarGroserias("m4lp4r1d0").inequivocas, ["malparido"]);
      assert.deepEqual(buscarGroserias("malpariiiiido").inequivocas, [
        "malparido",
      ]);
      assert.deepEqual(buscarGroserias("hijuepuuuta").inequivocas, [
        "hijueputa",
      ]);
    });

    it("las frases de varias palabras", () => {
      assert.ok(buscarGroserias("ese hijo de puta").inequivocas.includes(
        "hijo de puta",
      ));
      assert.ok(buscarGroserias("Vete a la mierda").inequivocas.includes(
        "vete a la mierda",
      ));
    });

    it("en inglés", () => {
      assert.deepEqual(buscarGroserias("What the fuck").inequivocas, ["fuck"]);
      assert.deepEqual(buscarGroserias("you motherfucker").inequivocas, [
        "motherfucker",
      ]);
    });

    it("en portugués", () => {
      assert.deepEqual(buscarGroserias("caralho, que calor").inequivocas, [
        "caralho",
      ]);
      assert.ok(buscarGroserias("foda-se").inequivocas.includes("foda se"));
      assert.ok(buscarGroserias("vai tomar no cu").inequivocas.includes(
        "vai tomar no cu",
      ));
    });
  });

  describe("deja las ambiguas para el administrador", () => {
    it("las que también tienen un uso inocente", () => {
      for (const [texto, palabra] of [
        ["Marica, qué ruta tan buena", "marica"],
        ["La gonorrea es una infección", "gonorrea"],
        ["Qué mierda de clima", "mierda"],
        ["Holy shit, new PR", "shit"],
        ["Porra, esqueci o relógio", "porra"],
      ]) {
        const resultado = buscarGroserias(texto);
        assert.deepEqual(resultado.ambiguas, [palabra], texto);
        assert.deepEqual(resultado.inequivocas, [], texto);
      }
    });
  });

  describe("no marca lo que no es grosería", () => {
    it("palabras que contienen una grosería", () => {
      for (const texto of [
        "Dejé el reloj en el computador",
        "Fue una disputa por el primer lugar",
        "Hicimos el assessment de la carrera",
        "Mi clase de spinning",
      ]) {
        assert.deepEqual(
          buscarGroserias(texto),
          { inequivocas: [], ambiguas: [] },
          texto,
        );
      }
    });

    it("el coloquial colombiano que la política permite", () => {
      assert.deepEqual(
        buscarGroserias("Qué chimba de ruta, parce, estuvo berraca"),
        { inequivocas: [], ambiguas: [] },
      );
    });

    it("el portugués y el inglés normales", () => {
      for (const texto of [
        "As pernas doem depois da corrida",
        "Corri 10K em 45 minutos",
        "Great run this morning, new personal best",
      ]) {
        assert.deepEqual(
          buscarGroserias(texto),
          { inequivocas: [], ambiguas: [] },
          texto,
        );
      }
    });

    it("los conos de los ejercicios de técnica", () => {
      assert.deepEqual(
        buscarGroserias("Pon los conos cada 10 metros"),
        { inequivocas: [], ambiguas: [] },
      );
    });
  });
});

describe("normalizarParaGroserias", () => {
  it("quita tildes, mayúsculas, signos y letras repetidas", () => {
    assert.equal(normalizarParaGroserias("¡¡PIROBOOO!!"), "pirobo");
    assert.equal(normalizarParaGroserias("Cuzão"), "cuzao");
  });

  it("lee los números como las letras que disimulan", () => {
    assert.equal(normalizarParaGroserias("h1ju3put4"), "hijueputa");
  });
});
