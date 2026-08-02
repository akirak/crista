// META: title=Mitochondria HTTP server interoperability
// META: global=window
// META: timeout=long

"use strict";

const mitochondriaBase = "http://127.0.0.1:8080";

promise_test(async () => {
  const response = await fetch(`${mitochondriaBase}/__mitochondria/status`);
  assert_equals(response.status, 200);
  assert_equals(response.headers.get("content-type"), "application/json");
  assert_object_equals(await response.json(), { status: "ok" });
}, "GET returns a status, headers, and a readable body");

promise_test(async () => {
  const value = "héllø from WPT";
  const response = await fetch(`${mitochondriaBase}/__mitochondria/echo`, {
    method: "POST",
    headers: { "Content-Type": "text/plain;charset=UTF-8" },
    body: value,
  });
  assert_equals(response.status, 200);
  assert_equals(response.headers.get("x-mitochondria-method"), "POST");
  assert_equals(await response.text(), value);
}, "POST request bodies survive a browser Fetch round trip");

promise_test(async () => {
  const response = await fetch(`${mitochondriaBase}/__mitochondria/status`, {
    method: "HEAD",
  });
  assert_equals(response.status, 200);
  assert_equals(await response.text(), "");
  assert_greater_than(Number(response.headers.get("content-length")), 0);
}, "HEAD preserves representation metadata and omits the response body");

promise_test(async () => {
  const response = await fetch(`${mitochondriaBase}/__mitochondria/redirect`);
  assert_true(response.redirected);
  assert_true(response.url.endsWith("/__mitochondria/status"));
  assert_equals(response.status, 200);
}, "Fetch follows an HTTP redirect emitted by the server");

promise_test(async () => {
  const responses = await Promise.all(
    Array.from({ length: 20 }, (_, index) =>
      fetch(`${mitochondriaBase}/__mitochondria/echo?request=${index}`)
    )
  );
  assert_true(responses.every(response => response.status === 200));
}, "The server handles concurrent browser requests");
