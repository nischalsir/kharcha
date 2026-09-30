import { assertEquals } from "jsr:@std/assert@1";

// Imported for `sign` only; importing the module also registers Deno.serve,
// which is harmless under `deno test`.
import { sign } from "../media-sign/index.ts";

// Worked example from Cloudinary's "Generating authentication signatures"
// docs, with its published result.
Deno.test("signature matches Cloudinary's documented example", async () => {
  const signature = await sign(
    {
      timestamp: "1315060510",
      public_id: "sample_image",
      eager: "w_400,h_300,c_pad|w_260,h_200,c_crop",
    },
    "abcd",
  );
  assertEquals(signature, "bfd09f95f331f558cbd1320e67aa8d488770583e");
});

Deno.test("params are signed in sorted order regardless of input order", async () => {
  const a = await sign({ b: "2", a: "1", c: "3" }, "s");
  const b = await sign({ c: "3", a: "1", b: "2" }, "s");
  assertEquals(a, b);
});
