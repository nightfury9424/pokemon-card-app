// Cloudflare Workers PoC — KREAM 메타몽(508949) 가격 GET 시도.
//
// 목적: cloudflare edge에서 cloudflare-hosted site (kream.co.kr) GET 가능한지 검증.
// AWS Lightsail Seoul + GitHub Actions Azure runner는 둘 다 HTTP 500 차단됨.
// cloudflare 자체 망 내부 통신은 bot detection 우회 가능성 ↑ (PoC).
//
// Deploy 후 URL GET 시 JSON 응답:
//   { status: 200, htmlSize: 254000, price: 207000, ok: true }
// 또는
//   { status: 500, htmlSize: 0, price: null, ok: false }

const KREAM_URL = "https://kream.co.kr/products/508949";

const HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
  Accept:
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  "Accept-Language": "ko-KR,ko;q=0.9,en;q=0.8",
  "Sec-Fetch-Dest": "document",
  "Sec-Fetch-Mode": "navigate",
  "Sec-Fetch-Site": "none",
  "Sec-Fetch-User": "?1",
  "Upgrade-Insecure-Requests": "1",
};

const PRICE_RE = /property="product:price:amount"\s+content="(\d+)"/i;

export default {
  async fetch(request, env, ctx) {
    try {
      const resp = await fetch(KREAM_URL, { headers: HEADERS });
      const html = await resp.text();
      const m = html.match(PRICE_RE);
      const price = m ? parseInt(m[1], 10) : null;
      return Response.json(
        {
          status: resp.status,
          htmlSize: html.length,
          price,
          ok: resp.status === 200 && price !== null,
          // 차단 시 처음 200자 보기
          preview: resp.status !== 200 ? html.slice(0, 200) : undefined,
        },
        {
          headers: {
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    } catch (err) {
      return Response.json(
        { error: String(err), ok: false },
        { status: 500 }
      );
    }
  },
};
