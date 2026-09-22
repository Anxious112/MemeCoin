// lb-phone injects fetchNui / onNuiEvent / resourceName / appName / settings
// into this iframe. In a browser preview (no lb-phone parent) those globals
// don't exist, so fall back to fetch() against the NUI resource name and a
// no-op event listener -- lets the page at least load without throwing.
const hasPhone = typeof fetchNui === 'function';

async function callNui(event, data) {
    if (hasPhone) {
        return fetchNui(event, data || {});
    }
    try {
        const res = await fetch(`https://${(typeof resourceName !== 'undefined' && resourceName) || 'anxious_memecoin'}/${event}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        return res.json();
    } catch (e) {
        return null;
    }
}

const state = {
    coins: [],
    portfolio: [],
    detail: null,
    tradeMode: 'buy',
    screen: 'market',
    createInfo: null,
};

const fmtMoney = (n) => {
    n = Number(n) || 0;
    if (Math.abs(n) >= 1e9) return '$' + (n / 1e9).toFixed(2) + 'B';
    if (Math.abs(n) >= 1e6) return '$' + (n / 1e6).toFixed(2) + 'M';
    if (Math.abs(n) >= 1e3) return '$' + (n / 1e3).toFixed(2) + 'K';
    return '$' + n.toFixed(n < 1 ? 6 : 2);
};

const fmtPrice = (n) => {
    n = Number(n) || 0;
    if (n === 0) return '$0.00';
    if (n < 0.0001) return '$' + n.toFixed(8);
    if (n < 1) return '$' + n.toFixed(6);
    return '$' + n.toFixed(4);
};

const fmtAmount = (n) => {
    n = Number(n) || 0;
    return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
};

function trendLabel(pct) {
    pct = Number(pct) || 0;
    if (pct >= 50) return { icon: '🚀', text: 'Rocketing', cls: 'up' };
    if (pct >= 5) return { icon: '📈', text: 'Pumping', cls: 'up' };
    if (pct <= -50) return { icon: '💀', text: 'Rugged Out', cls: 'down' };
    if (pct <= -5) return { icon: '📉', text: 'Dumping', cls: 'down' };
    return { icon: '➖', text: 'Flat', cls: 'flat' };
}

function coinInitials(coin) {
    return (coin.ticker || '?').slice(0, 3);
}

function coinIconHtml(coin) {
    if (coin.image) {
        return `<img src="${escapeAttr(coin.image)}" alt="">`;
    }
    return coinInitials(coin);
}

function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
}

function escapeAttr(s) {
    return escapeHtml(s);
}

function fmtRelativeTime(at) {
    if (!at) return 'just now';
    // MySQL DATETIME comes back as "YYYY-MM-DD HH:MM:SS" -- needs a "T" to
    // parse reliably across browsers.
    const d = new Date(String(at).replace(' ', 'T'));
    if (isNaN(d.getTime())) return '';
    const diffSec = Math.max(0, Math.round((Date.now() - d.getTime()) / 1000));
    if (diffSec < 5) return 'just now';
    if (diffSec < 60) return `${diffSec}s ago`;
    const diffMin = Math.round(diffSec / 60);
    if (diffMin < 60) return `${diffMin}m ago`;
    const diffHr = Math.round(diffMin / 60);
    if (diffHr < 24) return `${diffHr}h ago`;
    return `${Math.round(diffHr / 24)}d ago`;
}

// ---------- navigation ----------

function showScreen(name) {
    state.screen = name;
    document.querySelectorAll('.screen').forEach((el) => el.classList.remove('active'));
    document.getElementById(`screen-${name}`).classList.add('active');

    document.querySelectorAll('.nav-btn').forEach((btn) => {
        btn.classList.toggle('active', btn.dataset.screen === name);
    });

    const titles = { market: 'Market', portfolio: 'Portfolio', create: 'Launch', detail: state.detail ? `$${state.detail.ticker}` : 'Coin' };
    document.getElementById('pageTitle').textContent = titles[name] || 'Meme Coin';
    document.getElementById('navbar').classList.toggle('hidden', name === 'detail');
}

document.querySelectorAll('.nav-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
        const screen = btn.dataset.screen;
        showScreen(screen);
        if (screen === 'market') loadMarket();
        if (screen === 'portfolio') loadPortfolio();
    });
});

document.querySelectorAll('[data-back]').forEach((btn) => {
    btn.addEventListener('click', () => {
        showScreen(btn.dataset.back);
        loadMarket();
    });
});

document.getElementById('refreshBtn').addEventListener('click', () => {
    if (state.screen === 'market') loadMarket();
    else if (state.screen === 'portfolio') loadPortfolio();
    else if (state.screen === 'detail' && state.detail) openCoin(state.detail.id);
});

// ---------- market ----------

async function loadMarket() {
    const coins = await callNui('listCoins');
    state.coins = Array.isArray(coins) ? coins : [];
    renderMarket();
}

function renderMarket() {
    const list = document.getElementById('coinList');
    const empty = document.getElementById('marketEmpty');

    if (!state.coins.length) {
        list.innerHTML = '';
        empty.classList.remove('hidden');
        return;
    }
    empty.classList.add('hidden');

    list.innerHTML = state.coins.map((coin) => {
        const up = coin.change24h >= 0;
        return `
        <div class="coin-card" data-id="${coin.id}">
            <div class="coin-icon">${coinIconHtml(coin)}</div>
            <div class="coin-main">
                <div class="coin-ticker">$${escapeHtml(coin.ticker)}${coin.rugged ? '<span class="rug-badge">Rugged</span>' : ''}</div>
                <div class="coin-name">${escapeHtml(coin.name)}</div>
            </div>
            <div class="coin-right">
                <div class="coin-price">${fmtPrice(coin.price)}</div>
                <div class="coin-change ${up ? 'up' : 'down'}">${up ? '+' : ''}${coin.change24h}%</div>
            </div>
        </div>`;
    }).join('');

    list.querySelectorAll('.coin-card').forEach((card) => {
        card.addEventListener('click', () => openCoin(Number(card.dataset.id)));
    });
}

// ---------- portfolio ----------

async function loadPortfolio() {
    const rows = await callNui('getPortfolio');
    state.portfolio = Array.isArray(rows) ? rows : [];
    renderPortfolio();
}

function renderPortfolio() {
    const list = document.getElementById('portfolioList');
    const empty = document.getElementById('portfolioEmpty');

    if (!state.portfolio.length) {
        list.innerHTML = '';
        empty.classList.remove('hidden');
        return;
    }
    empty.classList.add('hidden');

    list.innerHTML = state.portfolio.map((row) => {
        const up = row.profitLoss >= 0;
        return `
        <div class="coin-card" data-id="${row.id}">
            <div class="coin-icon">${coinIconHtml(row)}</div>
            <div class="coin-main">
                <div class="coin-ticker">$${escapeHtml(row.ticker)}</div>
                <div class="coin-name">${fmtAmount(row.amount)} held</div>
            </div>
            <div class="coin-right">
                <div class="coin-price">${fmtMoney(row.value)}</div>
                <div class="coin-change ${up ? 'up' : 'down'}">${up ? '+' : ''}${fmtMoney(row.profitLoss)}</div>
            </div>
        </div>`;
    }).join('');

    list.querySelectorAll('.coin-card').forEach((card) => {
        card.addEventListener('click', () => openCoin(Number(card.dataset.id)));
    });
}

// ---------- coin detail ----------

async function openCoin(coinId) {
    showScreen('detail');
    const detail = await callNui('getCoinDetail', { coinId });
    if (!detail) {
        showScreen('market');
        return;
    }
    state.detail = detail;
    state.tradeMode = 'buy';
    document.querySelectorAll('.trade-tab').forEach((t) => t.classList.toggle('active', t.dataset.trade === 'buy'));
    document.getElementById('tradeAmount').value = '';
    document.getElementById('tradeQuote').textContent = '';
    document.getElementById('tradeMsg').textContent = '';
    renderDetail();
}

function renderDetail(flashLatestTrade) {
    const coin = state.detail;
    if (!coin) return;

    document.getElementById('pageTitle').textContent = `$${coin.ticker}`;

    const headerUp = (coin.change24h || 0) >= 0;

    document.getElementById('detailHeader').innerHTML = `
        <div class="coin-icon">${coinIconHtml(coin)}</div>
        <div class="detail-header-main">
            <div class="detail-header-name">${escapeHtml(coin.name)}${coin.rugged ? '<span class="rug-badge">Rugged</span>' : ''}</div>
            <div class="detail-header-ticker">$${escapeHtml(coin.ticker)} &middot; by ${escapeHtml(coin.creatorName)}</div>
        </div>
        <div class="detail-header-price">
            ${fmtPrice(coin.price)}
            <div class="coin-change ${headerUp ? 'up' : 'down'}">${headerUp ? '+' : ''}${coin.change24h || 0}% (24h)</div>
        </div>
    `;

    const trend = trendLabel(coin.changeSinceLaunch);
    const trendBanner = document.getElementById('trendBanner');
    trendBanner.className = `trend-banner trend-${trend.cls}`;
    trendBanner.innerHTML = `
        <span class="trend-icon">${trend.icon}</span>
        <span class="trend-text">${trend.text}<span class="trend-sub">since launch</span></span>
        <span class="trend-pct">${coin.changeSinceLaunch >= 0 ? '+' : ''}${coin.changeSinceLaunch}%</span>
    `;

    document.getElementById('detailStats').innerHTML = `
        <div class="stat-tile"><div class="stat-label">Market Cap</div><div class="stat-value">${fmtMoney(coin.marketCap)}</div></div>
        <div class="stat-tile"><div class="stat-label">Circulating</div><div class="stat-value">${fmtAmount(coin.circulating)}</div></div>
        <div class="stat-tile"><div class="stat-label">Total Supply</div><div class="stat-value">${fmtAmount(coin.totalSupply)}</div></div>
        <div class="stat-tile"><div class="stat-label">Status</div><div class="stat-value">${coin.rugged ? 'Rugged' : 'Active'}</div></div>
    `;

    drawChart(coin.chart || []);
    renderRecentTrades(flashLatestTrade);
    updateHoldingLine();

    document.getElementById('adminSection').classList.toggle('hidden', !coin.isAdmin);
    document.getElementById('deleteConfirmRow').classList.add('hidden');
    document.getElementById('deleteCoinBtn').classList.remove('hidden');
    document.getElementById('deleteMsg').textContent = '';
}

function renderRecentTrades(flashLatest) {
    const coin = state.detail;
    const list = document.getElementById('recentTrades');
    const empty = document.getElementById('recentTradesEmpty');
    const trades = (coin && coin.recentTrades) || [];

    if (!trades.length) {
        list.innerHTML = '';
        empty.classList.remove('hidden');
        return;
    }
    empty.classList.add('hidden');

    list.innerHTML = trades.map((t, i) => `
        <div class="trade-row${flashLatest && i === 0 ? ' trade-row-new' : ''}">
            <span class="trade-tag ${t.type}">${t.type}</span>
            <div class="trade-row-main">
                <div class="trade-row-name">${escapeHtml(t.traderName || 'Unknown')}</div>
                <div class="trade-row-time">${fmtRelativeTime(t.at)}</div>
            </div>
            <div class="trade-row-right">
                <div class="trade-row-amount">${t.type === 'buy' ? '+' : '-'}${fmtAmount(t.amount)} $${escapeHtml(coin.ticker)}</div>
                <div class="trade-row-currency">${fmtMoney(t.currency)}</div>
            </div>
        </div>
    `).join('');
}

function drawChart(points) {
    const canvas = document.getElementById('chart');
    const ctx = canvas.getContext('2d');
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    const styles = getComputedStyle(document.documentElement);
    const border = styles.getPropertyValue('--border').trim() || '#262b36';
    const dim = styles.getPropertyValue('--text-dim').trim() || '#8a90a0';

    ctx.strokeStyle = border;
    ctx.lineWidth = 1;
    for (let i = 1; i <= 3; i++) {
        const y = (h / 4) * i;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
        ctx.stroke();
    }

    if (!points.length) {
        ctx.fillStyle = dim;
        ctx.font = '12px sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText('No trades yet', w / 2, h / 2);
        return;
    }

    const prices = points.map((p) => Number(p.price));
    let min = Math.min(...prices), max = Math.max(...prices);
    if (min === max) { min *= 0.95; max *= 1.05; }
    const pad = 10;

    const up = prices[prices.length - 1] >= prices[0];
    const lineColor = up
        ? (styles.getPropertyValue('--up').trim() || '#29d98c')
        : (styles.getPropertyValue('--down').trim() || '#ff4d6d');

    ctx.beginPath();
    points.forEach((p, i) => {
        const x = points.length === 1 ? w / 2 : (i / (points.length - 1)) * (w - pad * 2) + pad;
        const y = h - pad - ((Number(p.price) - min) / (max - min)) * (h - pad * 2);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    });
    ctx.strokeStyle = lineColor;
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.stroke();

    if (points.length > 1) {
        const lastX = w - pad;
        const lastY = h - pad - ((prices[prices.length - 1] - min) / (max - min)) * (h - pad * 2);
        ctx.lineTo(lastX, h);
        ctx.lineTo(pad, h);
        ctx.closePath();
        ctx.fillStyle = lineColor.startsWith('#') ? lineColor + '22' : lineColor;
        ctx.fill();

        ctx.beginPath();
        ctx.arc(lastX, lastY, 3, 0, Math.PI * 2);
        ctx.fillStyle = lineColor;
        ctx.fill();
    }
}

function currentHolding() {
    if (!state.detail) return null;
    return state.portfolio.find((r) => r.id === state.detail.id) || null;
}

function updateHoldingLine() {
    const line = document.getElementById('holdingLine');
    const holding = currentHolding();
    if (state.tradeMode === 'sell') {
        line.textContent = holding ? `You hold ${fmtAmount(holding.amount)} $${state.detail.ticker}` : "You don't hold any of this coin.";
    } else {
        line.textContent = '';
    }
}

document.querySelectorAll('.trade-tab').forEach((tab) => {
    tab.addEventListener('click', () => {
        state.tradeMode = tab.dataset.trade;
        document.querySelectorAll('.trade-tab').forEach((t) => t.classList.toggle('active', t === tab));
        document.getElementById('tradeAmount').value = '';
        document.getElementById('tradeQuote').textContent = '';
        document.getElementById('tradeMsg').textContent = '';

        const submit = document.getElementById('tradeSubmit');
        submit.textContent = state.tradeMode === 'buy' ? 'Buy' : 'Sell';
        submit.classList.toggle('sell-mode', state.tradeMode === 'sell');

        document.getElementById('tradeAmount').placeholder = state.tradeMode === 'buy' ? 'Amount ($)' : 'Amount (tokens)';
        updateHoldingLine();
    });
});

document.getElementById('tradeAmount').addEventListener('input', (e) => {
    const val = Number(e.target.value);
    const quote = document.getElementById('tradeQuote');
    const coin = state.detail;
    if (!coin || !val || val <= 0) { quote.textContent = ''; return; }

    const k = coin.price * coin.circulating > 0 ? null : null;
    if (state.tradeMode === 'buy') {
        const approxTokens = val / coin.price;
        quote.textContent = `~${fmtAmount(approxTokens)} $${coin.ticker} at current price`;
    } else {
        const approxCurrency = val * coin.price;
        quote.textContent = `~${fmtMoney(approxCurrency)} at current price`;
    }
});

document.getElementById('tradeSubmit').addEventListener('click', async () => {
    const coin = state.detail;
    if (!coin) return;
    const amount = Number(document.getElementById('tradeAmount').value);
    const msg = document.getElementById('tradeMsg');
    msg.textContent = '';
    msg.className = 'trade-msg';

    if (!amount || amount <= 0) {
        msg.textContent = 'Enter an amount.';
        msg.classList.add('err');
        return;
    }

    const submit = document.getElementById('tradeSubmit');
    submit.disabled = true;

    const event = state.tradeMode === 'buy' ? 'buyCoin' : 'sellCoin';
    const res = await callNui(event, { coinId: coin.id, amount });
    submit.disabled = false;

    if (!res || !res.ok) {
        msg.textContent = (res && res.result) || 'Trade failed.';
        msg.classList.add('err');
        return;
    }

    msg.textContent = state.tradeMode === 'buy'
        ? `Bought ${fmtAmount(res.result.tokensOut)} $${coin.ticker}.`
        : `Sold for ${fmtMoney(res.result.currencyOut)}.`;
    msg.classList.add('ok');
    document.getElementById('tradeAmount').value = '';
    document.getElementById('tradeQuote').textContent = '';

    await loadPortfolio();
    await openCoin(coin.id);
});

// ---------- admin ----------

document.getElementById('deleteCoinBtn').addEventListener('click', () => {
    document.getElementById('deleteCoinBtn').classList.add('hidden');
    document.getElementById('deleteConfirmRow').classList.remove('hidden');
});

document.getElementById('deleteCancelBtn').addEventListener('click', () => {
    document.getElementById('deleteConfirmRow').classList.add('hidden');
    document.getElementById('deleteCoinBtn').classList.remove('hidden');
});

document.getElementById('deleteConfirmBtn').addEventListener('click', async () => {
    const coin = state.detail;
    if (!coin) return;

    const btn = document.getElementById('deleteConfirmBtn');
    const msg = document.getElementById('deleteMsg');
    btn.disabled = true;

    const res = await callNui('deleteCoin', { coinId: coin.id });
    btn.disabled = false;

    if (!res || !res.ok) {
        msg.textContent = (res && res.result) || 'Could not delete coin.';
        msg.className = 'trade-msg err';
        return;
    }

    state.coins = state.coins.filter((c) => c.id !== coin.id);
    showScreen('market');
    renderMarket();
});

// ---------- create ----------

document.getElementById('createSubmit').addEventListener('click', async () => {
    const name = document.getElementById('createName').value.trim();
    const ticker = document.getElementById('createTicker').value.trim();
    const image = document.getElementById('createImage').value.trim();
    const msg = document.getElementById('createMsg');
    msg.textContent = '';
    msg.className = 'trade-msg';

    if (!name || !ticker) {
        msg.textContent = 'Name and ticker are required.';
        msg.classList.add('err');
        return;
    }

    const submit = document.getElementById('createSubmit');
    submit.disabled = true;
    const res = await callNui('createCoin', { name, ticker, image: image || null });
    submit.disabled = false;

    if (!res || !res.ok) {
        msg.textContent = (res && res.result) || 'Could not launch coin.';
        msg.classList.add('err');
        return;
    }

    msg.textContent = `$${res.ticker} is live!`;
    msg.classList.add('ok');
    document.getElementById('createName').value = '';
    document.getElementById('createTicker').value = '';
    document.getElementById('createImage').value = '';

    await loadMarket();
    setTimeout(() => showScreen('market'), 600);
});

// ---------- create info ----------

async function loadCreateInfo() {
    state.createInfo = await callNui('getCreateInfo');
    renderCreateInfo();
}

function renderCreateInfo() {
    const el = document.getElementById('createCost');
    const info = state.createInfo;
    if (!info) { el.textContent = ''; return; }
    const total = Number(info.createCost) + Number(info.creatorInitialBuy);
    el.textContent = `$${info.createCost} launch fee + $${info.creatorInitialBuy} starter buy = $${total} total -- the starter buy gives you real tokens in your own coin.`;
}

// ---------- push events from the server ----------

if (typeof onNuiEvent === 'function') {
    onNuiEvent('priceUpdate', (data) => {
        const trade = data.trade || {};
        const newPrice = Number(trade.price);

        const coin = state.coins.find((c) => c.id === data.coinId);
        if (coin) {
            coin.price = newPrice;
            if (state.screen === 'market') renderMarket();
        }

        const holdingRow = state.portfolio.find((r) => r.id === data.coinId);
        if (holdingRow) {
            holdingRow.currentPrice = newPrice;
            holdingRow.value = Math.round(newPrice * holdingRow.amount * 100) / 100;
            holdingRow.profitLoss = Math.round((newPrice - holdingRow.avgBuyPrice) * holdingRow.amount * 100) / 100;
            if (state.screen === 'portfolio') renderPortfolio();
        }

        // Grow the open coin's chart and trade feed live instead of making
        // the player back out and reopen it to see the pump/dump land.
        if (state.detail && state.detail.id === data.coinId) {
            const d = state.detail;
            d.price = newPrice;
            d.chart = (d.chart || []).concat([{ price: newPrice, at: trade.at || new Date().toISOString() }]);

            const launchPrice = d.chart[0] ? Number(d.chart[0].price) : newPrice;
            d.changeSinceLaunch = launchPrice > 0 ? Math.round(((newPrice - launchPrice) / launchPrice) * 10000) / 100 : 0;

            if (trade.amount > 0) {
                d.recentTrades = [trade].concat(d.recentTrades || []).slice(0, 15);
            }

            if (state.screen === 'detail') renderDetail(true);
        }
    });

    onNuiEvent('coinDeleted', (data) => {
        state.coins = state.coins.filter((c) => c.id !== data.coinId);
        state.portfolio = state.portfolio.filter((r) => r.id !== data.coinId);

        if (state.screen === 'market') renderMarket();
        if (state.screen === 'portfolio') renderPortfolio();

        if (state.detail && state.detail.id === data.coinId) {
            state.detail = null;
            showScreen('market');
            renderMarket();
        }
    });
}

// ---------- boot ----------

function init() {
    loadMarket();
    loadPortfolio();
    loadCreateInfo();
}

if (typeof window.addEventListener === 'function') {
    window.addEventListener('message', (e) => {
        if (e.data && e.data.action === 'componentsLoaded') init();
    });
}

// Fallback for the case lb-phone's componentsLoaded ping never arrives
// (e.g. a plain browser preview) -- boot after a short delay regardless.
setTimeout(init, 300);
