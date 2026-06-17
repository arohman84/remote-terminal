# Remote Terminal

A standalone Project Zomboid mod that introduces a **remote-accessible warehouse network** — no dependencies, no chunk scanning.

Build Packers and Terminals in the world to create a storage network, then craft a handheld **Remote Terminal** device to browse and transfer items from **anywhere** — even when far away or the chunk isn't loaded.

---

## Features

- **Two access methods**: Walk up to a Terminal (same UX as WarehouseTerminal) or use the handheld Remote Terminal device from anywhere
- **Global network table**: Server-authoritative `RemoteTerminal.Network` — no chunk-radius scanning, instant IP lookups
- **No dependencies**: Completely standalone; does not require WarehouseTerminal or any other mod
- **Battery-powered handheld device**: Craftable, rechargeable at running generators
- **Cold storage routing**: Perishable food automatically routed to fridges/freezers
- **PIN security**: Optional 4-digit PINs on devices, terminals, and packers
- **Container linking**: Link any world container (crates, fridges, freezers) to your terminal network
- **Item routing rules**: Filter by category or specific item type per terminal
- **Sandbox options**: Configurable battery capacity, drain rate, and recharge time

---

## Getting Started

### 1. Build the Network

Open the build menu and navigate to **Build → Remote Terminals**:

| Object | Materials | Skills Required |
|--------|-----------|-----------------|
| **Remote Packer** | 6 SheetMetal, 4 MetalPipe, 6 Plank, 2 ElectricWire, 2 Wire | Carpentry 6, MetalWelding 4 |
| **Remote Terminal** | 6 SheetMetal, 4 MetalPipe, 6 Plank | Carpentry 6, MetalWelding 4 |

- **Packer** — The network hub. Generates a random IP address on placement. Holds no items; routes between terminals.
- **Terminal** — Storage access point. Has its own container and can link to nearby containers. Must be configured with a Packer IP.

### 2. Configure the Terminal

Right-click a placed Terminal and select **Open Remote Terminal**:

1. **Set Packer IP** — Enter the IP of your Packer (right-click the Packer to view its IP)
2. **Set Terminal PIN** (optional) — 4-digit security PIN
3. **Link Container** — Stand near a container and click to add it to the network

### 3. Craft the Handheld Device

| Recipe | Materials | Skill |
|--------|-----------|-------|
| **Craft Remote Terminal** | 6 ElectronicsScrap, 3 ElectricWire, 2 Aluminum, 4 Screws | Electricity 2 |

The device appears in your inventory as a radio-type attachment.

### 4. Connect Remotely

Right-click the Remote Terminal in your inventory:

1. **Open Remote Terminal** — Enter your Packer's IP and click Connect
2. Browse items, transfer in/out of the network — works from anywhere on the map
3. **Recharge** at a running generator when battery is low (right-click → Recharge)

---

## Usage

### Walk-Up Terminal (Right-Click World Object)

| Action | Description |
|--------|-------------|
| **Take One / Half / All** | Transfer selected items from the network to your inventory |
| **Store Selected / All** | Transfer matching items from your inventory into the network |
| **Set Packer IP** | Change which Packer this terminal connects to |
| **Set Terminal PIN** | Add or change the 4-digit access PIN |
| **Link Container** | Register a nearby container with this terminal |
| **Refresh** | Reload network state from the server |

### Handheld Device (Right-Click Inventory Item)

| Action | Description |
|--------|-------------|
| **Open Remote Terminal** | Connect to a Packer by IP and browse the network |
| **Set/Change Device PIN** | Lock the device with a 4-digit PIN |
| **Recharge** | Full recharge at a running generator (within 3 tiles) |

### View Tabs

- **Name** — Alphabetical list of all items
- **Category** — Grouped by item category
- **Fridge** — Only items stored in refrigerated containers
- **Freezer** — Only items stored in freezer containers

### Cold Storage

Perishable food items are automatically routed to fridges and freezers when storing from your inventory. Items with `*` have freezer storage; items with `~` have fridge storage.

---

## Architecture

```
┌──────────────────────────────────────────────┐
│        SERVER: RemoteTerminal.Network         │
│  Global table (in-memory) + ModData (disk)    │
│                                                │
│  packers["192.168.1.10"] → {x, y, z, pin}     │
│  terminals["TERM01"] → {packerIP, containers}  │
│  inventorySnapshots → cached container data    │
│                                                │
│         ↕ sendClientCommand/sendServerCommand  │
├──────────────────────────────────────────────┤
│  CLIENT                                        │
│  ┌─────────────────┐  ┌────────────────────┐  │
│  │ Walk-Up Terminal│  │ Handheld Device    │  │
│  │ (world object)  │  │ (inventory item)   │  │
│  └─────────────────┘  └────────────────────┘  │
└──────────────────────────────────────────────┘
```

**Key difference from WarehouseTerminal**: No `findWarehouseTerminalsForPacker()` radius scanning. The global table *is* the network — instant lookup by IP, always available.

---

## Sandbox Options

| Option | Default | Range | Description |
|--------|---------|-------|-------------|
| Battery Capacity | 100 | 10–999 | Maximum charge of the handheld device |
| Battery Drain Per Item | 2.0 | 0.1–100 | Battery points consumed per item transferred |
| Recharge Time (ms) | 6000 | 100–30000 | Time to fully recharge at a generator |

---

## Multiplayer

Fully multiplayer-compatible. The server maintains the `RemoteTerminal.Network` global table. All inventory transfers go through server commands, so remote access works regardless of which chunks are loaded on any given client.

---

## Credits

This mod is built upon and heavily inspired by the **Warehouse Terminal** mod (Workshop ID: `3724485065`, Mod ID: `WarehouseTerminal_Balanced`), which pioneered the Packer/Terminal network concept, IP-based addressing, container linking, cold storage routing, and the two-panel inventory UI in Project Zomboid.

The Remote Terminal mod reimagines the Warehouse Terminal architecture with a **server-side global data table** (`RemoteTerminal.Network`) in place of chunk-radius scanning, adds a **crafted handheld device** for remote access from anywhere on the map, and is fully standalone with no external mod dependencies.

Special thanks to the Warehouse Terminal mod author(s) for their innovative work that made this mod possible.

---

## License

This mod is provided as-is for the Project Zomboid community. Feel free to modify and redistribute with attribution.
