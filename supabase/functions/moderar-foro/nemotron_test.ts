// Pruebas del cliente de Nemotron (SCRUM-335), sin red: `fetch` es falso.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  consultarNemotron,
  ErrorNemotron,
  leerVeredicto,
  solicitud,
} from "./nemotron.ts";
import { POLITICA_TRAZA } from "./politica_traza.ts";

describe("leerVeredicto", () => {
  it("lee un texto seguro", () => {
    assert.deepEqual(leerVeredicto("User Safety: safe"), {
      seguro: true,
      categorias: [],
    });
  });

  it("lee un texto inseguro con sus categorías", () => {
    assert.deepEqual(
      leerVeredicto(
        "User Safety: unsafe\nSafety Categories: Harassment, Profanity",
      ),
      { seguro: false, categorias: ["Harassment", "Profanity"] },
    );
  });

  it("ignora lo que el modelo dice mientras razona", () => {
    const respuesta = [
      "<think>",
      "Podría ser User Safety: unsafe por el tono, pero es un consejo de",
      "entrenamiento. Safety Categories: Harassment no aplica.",
      "</think>User Safety: safe",
    ].join("\n");

    assert.deepEqual(leerVeredicto(respuesta), { seguro: true, categorias: [] });
  });

  it("falla si el razonamiento quedó sin cerrar", () => {
    assert.throws(
      () => leerVeredicto("<think>Evaluando... User Safety: safe"),
      ErrorNemotron,
    );
  });

  it("falla si la respuesta no trae el veredicto", () => {
    assert.throws(() => leerVeredicto("No sé"), ErrorNemotron);
  });

  it("no toma 'None' como categoría", () => {
    assert.deepEqual(
      leerVeredicto("User Safety: unsafe\nSafety Categories: None"),
      { seguro: false, categorias: [] },
    );
  });
});

describe("solicitud", () => {
  it("la taxonomía pide categorías sin razonamiento ni política", () => {
    const cuerpo = solicitud("hola", "taxonomia", "modelo");
    assert.deepEqual(cuerpo.chat_template_kwargs, {
      request_categories: "/categories",
      enable_thinking: false,
    });
    assert.equal(cuerpo.max_tokens, 100);
  });

  it("la política lleva las normas de TRAZA y razona", () => {
    const cuerpo = solicitud("hola", "politica", "modelo");
    assert.deepEqual(cuerpo.chat_template_kwargs, {
      request_categories: "/categories",
      enable_thinking: true,
      custom_policy: POLITICA_TRAZA,
    });
    assert.equal(cuerpo.max_tokens, 800);
  });

  it("manda el texto como mensaje del usuario", () => {
    const cuerpo = solicitud("¿Cómo bajo mi ritmo?", "taxonomia", "modelo");
    assert.deepEqual(cuerpo.messages, [
      {
        role: "user",
        content: [{ type: "text", text: "¿Cómo bajo mi ritmo?" }],
      },
    ]);
  });
});

function fetchQueResponde(
  status: number,
  cuerpo: unknown,
  pedidos: Array<{ url: string; init: RequestInit }> = [],
): typeof fetch {
  return ((url: string, init: RequestInit) => {
    pedidos.push({ url, init });
    return Promise.resolve(
      new Response(JSON.stringify(cuerpo), {
        status,
        headers: { "Content-Type": "application/json" },
      }),
    );
  }) as unknown as typeof fetch;
}

const configuracion = {
  apiKey: "clave",
  url: "https://nvidia.test/v1/chat/completions",
  modelo: "nvidia/nemotron-3.5-content-safety",
  timeoutMs: 1000,
};

describe("consultarNemotron", () => {
  it("devuelve el veredicto y la respuesta cruda", async () => {
    const pedidos: Array<{ url: string; init: RequestInit }> = [];
    const respuesta = {
      choices: [{ message: { content: "User Safety: unsafe\nSafety Categories: Profanity" } }],
    };

    const veredicto = await consultarNemotron("texto", "taxonomia", {
      ...configuracion,
      fetch: fetchQueResponde(200, respuesta, pedidos),
    });

    assert.equal(veredicto.seguro, false);
    assert.deepEqual(veredicto.categorias, ["Profanity"]);
    assert.match(veredicto.crudo, /Profanity/);
    assert.equal(pedidos[0].url, configuracion.url);
    assert.equal(
      (pedidos[0].init.headers as Record<string, string>).Authorization,
      "Bearer clave",
    );
  });

  it("falla con ErrorNemotron si NVIDIA responde un error", async () => {
    await assert.rejects(
      consultarNemotron("texto", "taxonomia", {
        ...configuracion,
        fetch: fetchQueResponde(429, { error: "rate limit" }),
      }),
      ErrorNemotron,
    );
  });

  it("falla con ErrorNemotron si NVIDIA no responde a tiempo", async () => {
    const colgado = ((_: string, init: RequestInit) =>
      new Promise((_resolver, rechazar) => {
        init.signal?.addEventListener("abort", () => rechazar(new Error("abort")));
      })) as unknown as typeof fetch;

    await assert.rejects(
      consultarNemotron("texto", "taxonomia", {
        ...configuracion,
        timeoutMs: 10,
        fetch: colgado,
      }),
      (error: unknown) =>
        error instanceof ErrorNemotron && /no respondió/.test(error.message),
    );
  });
});
