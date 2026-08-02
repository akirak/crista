// META: title=Crista HTTP server interoperability
// META: global=window
// META: timeout=long

"use strict";

const cristaBase = "http://127.0.0.1:8080";

promise_test(async () => {
  const response = await fetch(`${cristaBase}/__crista/status`);
  assert_equals(response.status, 200);
  assert_equals(response.headers.get("content-type"), "application/json");
  assert_object_equals(await response.json(), { status: "ok" });
}, "GET returns a status, headers, and a readable body");

promise_test(async () => {
  const value = "héllø from WPT";
  const response = await fetch(`${cristaBase}/__crista/echo`, {
    method: "POST",
    headers: { "Content-Type": "text/plain;charset=UTF-8" },
    body: value,
  });
  assert_equals(response.status, 200);
  assert_equals(response.headers.get("x-crista-method"), "POST");
  assert_equals(await response.text(), value);
}, "POST request bodies survive a browser Fetch round trip");

promise_test(async () => {
  const response = await fetch(`${cristaBase}/__crista/status`, {
    method: "HEAD",
  });
  assert_equals(response.status, 200);
  assert_equals(await response.text(), "");
  assert_greater_than(Number(response.headers.get("content-length")), 0);
}, "HEAD preserves representation metadata and omits the response body");

promise_test(async () => {
  const response = await fetch(`${cristaBase}/__crista/redirect`);
  assert_true(response.redirected);
  assert_true(response.url.endsWith("/__crista/status"));
  assert_equals(response.status, 200);
}, "Fetch follows an HTTP redirect emitted by the server");

promise_test(async () => {
  const responses = await Promise.all(
    Array.from({ length: 20 }, (_, index) =>
      fetch(`${cristaBase}/__crista/echo?request=${index}`)
    )
  );
  assert_true(responses.every(response => response.status === 200));
}, "The server handles concurrent browser requests");
