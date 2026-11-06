var bigInt = require("big-integer");

// ---------------------------------------------------------------------------
// Estado a nivel de modulo: se crea cuando el worker de Node carga la funcion
// y vive mientras ESA instancia siga activa. Si Azure recicla la instancia por
// inactividad, o la peticion cae en otra instancia, el memo arranca vacio.
// ---------------------------------------------------------------------------
const memo = new Map([[0, bigInt.zero], [1, bigInt.one]]);
const loadedAt = new Date();
let invocations = 0;

// Fibonacci recursivo con memoization (top-down).
function fib(n) {
    if (memo.has(n)) return memo.get(n);
    const value = fib(n - 1).add(fib(n - 2));
    memo.set(n, value);
    return value;
}

module.exports = async function (context, req) {
    invocations++;
    context.log('FibonacciMemo: peticion recibida.');

    const raw = (req.body && req.body.nth !== undefined) ? req.body.nth : req.query.nth;
    const nth = Number(raw);
    if (!Number.isInteger(nth) || nth < 0) {
        context.res = { status: 400, body: "nth debe ser un entero mayor o igual a 0" };
        return;
    }

    const instance = {
        instanceId: (process.env.WEBSITE_INSTANCE_ID || "local").substring(0, 12),
        pid: process.pid,
        loadedAt: loadedAt.toISOString(),
        uptimeSec: Math.round(process.uptime()),
        invocationsOnThisInstance: invocations
    };
    const fromCache = memo.has(nth);
    const memoSizeBefore = memo.size;
    const start = process.hrtime.bigint();

    try {
        const answer = fib(nth);
        const elapsedMs = Number(process.hrtime.bigint() - start) / 1e6;
        const value = answer.toString();
        context.log(`nth=${nth} fromCache=${fromCache} memo=${memoSizeBefore}->${memo.size} t=${elapsedMs.toFixed(2)}ms`);
        context.res = {
            headers: { "Content-Type": "application/json" },
            body: {
                nth,
                fromCache,
                memoSizeBefore,
                memoSizeAfter: memo.size,
                elapsedMs: Number(elapsedMs.toFixed(3)),
                digits: value.length,
                ...instance,
                value
            }
        };
    } catch (err) {
        const elapsedMs = Number(process.hrtime.bigint() - start) / 1e6;
        context.log.error(`nth=${nth} fallo: ${err.name}: ${err.message}`);
        context.res = {
            status: 500,
            headers: { "Content-Type": "application/json" },
            body: {
                nth,
                error: `${err.name}: ${err.message}`,
                memoSize: memo.size,
                elapsedMs: Number(elapsedMs.toFixed(3)),
                ...instance
            }
        };
    }
};
