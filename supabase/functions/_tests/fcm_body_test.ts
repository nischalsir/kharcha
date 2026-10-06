import { assert, assertEquals } from "jsr:@std/assert@1";

import { buildFcmBody, pictureUrl, systemDrawn } from "../_shared/fcm.ts";

// A notification that only shows while the app is open is not a notification.
// These pin the one thing that makes it arrive on a closed app (Android draws
// it), and the one thing that would make it arrive twice (sending that shape
// to an app that still draws everything itself).

const data = {
  category: "daily_buddy",
  title: "Good morning",
  body: "A fresh day. Tea first, then the budget.",
  route: "/",
};

Deno.test("only an app that knows about it is sent a system-drawn message", () => {
  for (const version of ["2.3.0", "2.3.1", "2.10.0", "3.0.0", "v2.3.0", "2.3.0+40"]) {
    assert(systemDrawn(version), version);
  }
  for (
    const version of ["2.2.0", "2.2.9", "1.9.0", "2.2", "", "junk", null, undefined]
  ) {
    assert(!systemDrawn(version), String(version));
  }
});

Deno.test("an older app, or one that never said its version, gets data only", () => {
  for (const appVersion of ["2.2.0", null, undefined]) {
    const body = buildFcmBody({
      token: "t",
      appVersion,
      data,
      android: { priority: "high", ttl: "7200s", collapseKey: "daily-buddy" },
    });
    assertEquals(body, {
      token: "t",
      data,
      android: { priority: "high", ttl: "7200s", collapseKey: "daily-buddy" },
    });
  }
});

Deno.test("a current app gets the notification for Android to draw, and the data", () => {
  const body = buildFcmBody({
    token: "t",
    appVersion: "2.3.0",
    data,
    android: { priority: "high", ttl: "7200s", collapseKey: "daily-buddy" },
  });
  assertEquals(body, {
    token: "t",
    // Still all of it: the open app draws from this, and a tap is routed by it.
    data,
    notification: { title: data.title, body: data.body },
    android: {
      priority: "high",
      ttl: "7200s",
      collapseKey: "daily-buddy",
      // The category's own channel, and one greeting replaces the last.
      notification: { channelId: "kharcha_insights", tag: "daily-buddy" },
    },
  });
  // The version decides the shape and is never sent.
  assert(!("appVersion" in body));
});

Deno.test("the channel follows the category, with the general one as fallback", () => {
  const channel = (category: string) =>
    (buildFcmBody({
      token: "t",
      appVersion: "2.3.0",
      data: { ...data, category },
    }).android as { notification: { channelId: string; tag?: string } })
      .notification;
  assertEquals(channel("budget_warnings"), { channelId: "kharcha_budget" });
  assertEquals(channel("recurring_reminders"), {
    channelId: "kharcha_reminders",
  });
  assertEquals(channel("something_new"), { channelId: "kharcha_default" });
});

Deno.test("a topic, or a message with nothing to show, stays data only", () => {
  assertEquals(
    buildFcmBody({ topic: "all", appVersion: "2.3.0", data }),
    { topic: "all", data },
  );
  const silent = { category: "daily_buddy", title: "", body: "" };
  assertEquals(
    buildFcmBody({ token: "t", appVersion: "2.3.0", data: silent }),
    { token: "t", data: silent },
  );
});

Deno.test("a picture is given to Android to draw, and only over https", () => {
  const picture = "https://example.com/offer.jpg";
  const drawn = (image: string) =>
    (buildFcmBody({
      token: "t",
      appVersion: "2.3.0",
      data: { ...data, image },
    }).android as { notification: { image?: string } }).notification.image;
  assertEquals(drawn(picture), picture);
  for (const bad of ["http://example.com/offer.jpg", "offer.jpg", "", " "]) {
    assertEquals(drawn(bad), undefined, bad);
  }
  assertEquals(pictureUrl(` ${picture} `), picture);
  assertEquals(pictureUrl(undefined), undefined);

  // An older app draws it itself, from the data it was always sent.
  const older = buildFcmBody({ token: "t", data: { ...data, image: picture } });
  assertEquals(older, { token: "t", data: { ...data, image: picture } });
});
