# NetSync

*[Read in English](README.md)*

Kerangka kerja (framework) jaringan satu-modul untuk Roblox. Mengimplementasikan arsitektur RemoteEvent tunggal yang dilengkapi fitur *payload batching* dan *rate limiting* berbasis *token-bucket*.

## Fitur
- **Strict Typing:** Ditulis seluruhnya menggunakan strict Luau.
- **Identifier Compression:** Secara otomatis menghash string nama event menjadi integer 16-bit via DJB2, memangkas drastis penggunaan *bandwidth*.
- **Payload Batching:** Secara otomatis mengantrekan permintaan klien dan menembakkannya secara kolektif di akhir satu *frame* melalui `RunService.Heartbeat`.
- **Rate Limiting:** Algoritma *token-bucket* pada sisi server untuk mengatur frekuensi permintaan data yang masuk dari tiap pemain.
- **Arsitektur Remote Tunggal:** Merutekan seluruh lalu lintas data melalui satu `RemoteEvent` yang dibuat secara dinamis.

## Metrik Performa (V1.5)
Di bawah tekanan *stress test* tersimulasi yang melibatkan 50 pemain tempur dengan lebih dari 3.300+ paket data masuk berkecepatan tinggi per detik:
- **Server CPU Time:** Tetap stabil sempurna pada ~16.1ms (batas 60 FPS) saat diuji dari dalam Roblox Studio penuh jendela.
- **Total DataCost:** Ratusan event dari puluhan pemain berhasil dikompresi menjadi pengeluaran hanya ~161 KB/s data agregat keseluruhan.
- **Network Ping:** Stabil di angka 0-15ms, dengan membuktikan batas hambatan penumpukan *packet* sama dengan nol.

## Penggunaan

### 1. Instalasi
Letakkan ModuleScript `NetSync.luau` ke dalam `ReplicatedStorage`. 

### 2. Contoh Penggunaan

**Contoh Kode Server**
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetSync = require(ReplicatedStorage.NetSync)

-- Opsional: Konfigurasi batas permintaan, default adalah 20 req/s
NetSync.configureRateLimit({
    MaxRequestsPerSecond = 30,
    Punishment = "Drop" -- Opsi: "Drop" atau "Kick"
})

-- Mendengarkan (listen) sebuah sinyal event
NetSync.listen("WeaponFire", function(player, data)
    print(`Menerima data senjata dari {player.Name}`)
    NetSync.fire(player, "HitConfirmation", { target = data.target })
end)
```

**Contoh Kode Client**
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetSync = require(ReplicatedStorage.NetSync)

-- Mendengarkan event dari server
NetSync.listen("HitConfirmation", function(data)
    print(`Server mengonfirmasi hit pada: {data.target}`)
end)

-- Menembakkan event (akan diproses batch secara otomatis)
NetSync.fire("WeaponFire", { target = "Model1" })
NetSync.fire("UpdatePosition", { x = 10, y = 20 })
```

## Referensi API

### `NetSync` (Fungsi Bersama / Shared)
- `listen(eventName: string, callback: (...any) -> ())`: Memasang *listener* pada sebuah event.

### `NetSync` (Fungsi Khusus Server)
- `fire(player: Player, eventName: string, data: any)`: Mengirim *payload* data ke satu pemain tertentu.
- `fireAll(eventName: string, data: any)`: Mengirim *payload* data ke semua pemain yang terkoneksi.
- `configureRateLimit(config: RateLimitConfig)`: Memperbarui konfigurasi *rate-limiting*.

### `NetSync` (Fungsi Khusus Client)
- `fire(eventName: string, data: any)`: Memasukkan *payload* data ke dalam antrean untuk dikirim ke server pada pergerakan layar (*frame*) berikutnya.
