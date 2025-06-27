document.addEventListener('DOMContentLoaded', () => {
    const tabletContainer = document.querySelector('body');
    const closeButton = document.getElementById('close-tablet-btn');
    const statusBar = document.getElementById('status-bar');

    const adminControls = document.querySelectorAll('.admin-controls');
    const forceBlackoutBtn = document.getElementById('force-blackout-btn');
    const repairPowerBtn = document.getElementById('repair-power-btn');
    const powerZoneSelect = document.getElementById('power-zone-select');

    const reportDumpingBtn = document.getElementById('report-dumping-btn');

    // Cache for NUI state to avoid re-querying DOM too much
    const Internet = {
        PlayerSubscriptions: {}, // { property_id: { details }}
        PendingInstallations: {}, // { property_id: { details }}
        HubsState: {} // { hub_id: { details }}
    };
    window.cachedConfigData = { Internet: { ServiceTiers: {} } }; // Cache relevant config

    const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'fivem-smart-utilities';

    async function postNuiMessage(eventName, data = {}) {
        try {
            const resp = await fetch(`https://${resourceName}/${eventName}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8', },
                body: JSON.stringify(data),
            });
            return await resp.json();
        } catch (e) {
            console.error(`Error sending NUI message ${eventName}:`, e);
            return null;
        }
    }

    function showTablet() {
        tabletContainer.classList.remove('hidden');
        statusBar.textContent = 'Connected. Fetching latest data...';
        // NUI_READY is sent once on load, server should send initial data then.
    }

    function hideTablet() {
        tabletContainer.classList.add('hidden');
        postNuiMessage('NUI_CLOSE');
    }

    if (closeButton) {
        closeButton.addEventListener('click', hideTablet);
    }

    window.addEventListener('message', (event) => {
        const { type, dataType, payload } = event.data;

        if (type === 'NUI_SHOW') {
            showTablet();
        } else if (type === 'NUI_HIDE') {
            hideTablet();
        } else if (type === 'UPDATE_DATA') {
            console.log("Received data update from Lua:", dataType, payload);
            statusBar.textContent = 'System data updated.';

            if (dataType === 'initial_load') {
                // Cache parts of config needed by dynamic UI renders
                if (payload.config && payload.config.Internet && payload.config.Internet.ServiceTiers) {
                    window.cachedConfigData.Internet.ServiceTiers = payload.config.Internet.ServiceTiers;
                }
                if (payload.internet && payload.internet.hubs) { // Cache initial hub states
                    Internet.HubsState = payload.internet.hubs;
                }
                if (payload.internet && payload.internet.subscriptions) { // Cache initial subscriptions
                    Internet.PlayerSubscriptions = payload.internet.subscriptions;
                }
                 if (payload.internet && payload.internet.pendingInstallations) { // Cache initial pending installs
                    Internet.PendingInstallations = payload.internet.pendingInstallations;
                }
                updateAllModules(payload); // This will use cached data too
                checkAdminPermissions(payload.isAdmin);
            } else if (dataType === 'power_status') {
                updatePowerModule(payload);
            } else if (dataType === 'water_status') {
                updateWaterModule(payload);
            } else if (dataType === 'water_leak_update') {
                updateWaterLeakStatus(payload);
            } else if (dataType === 'internet_status') { // Full update of hubs
                if (payload.hubs) {
                    Internet.HubsState = payload.hubs; // Update cache
                    updateInternetModule(payload.hubs);
                }
                 // If payload.userService is sent with general internet_status, update relevant property
                if (payload.userService && payload.userService.propertyId) {
                    updateUserSpecificInternetService(payload.userService, payload.userService.propertyId);
                } else if (payload.userService) { // A general update not tied to a specific property card (if any)
                     console.log("General userService update (no propertyId):", payload.userService);
                }

            } else if (dataType === 'internet_hub_status') {
                for(const hubId in payload){ // Update HubsState cache
                    if(Internet.HubsState[hubId]) Internet.HubsState[hubId] = {...Internet.HubsState[hubId], ...payload[hubId]};
                    else Internet.HubsState[hubId] = payload[hubId];
                }
                updateInternetModule(payload);
            } else if (dataType === 'internet_user_service') {
                // payload: { propertyId, citizenid, provider, speed_tier, is_active, last_payment }
                // This is an update for a single property's subscription.
                if (payload && payload.propertyId) {
                    Internet.PlayerSubscriptions[payload.propertyId] = payload; // Update cache
                    if (payload.is_active && Internet.PendingInstallations[payload.propertyId]) { // If just activated, remove from pending
                        delete Internet.PendingInstallations[payload.propertyId];
                    }
                    // Re-render the specific property card
                    updateUserSpecificInternetService(payload, payload.propertyId);
                }
            } else if (dataType === 'internet_pending_install_update') { // New or updated pending install
                if(payload && payload.property_id) {
                    Internet.PendingInstallations[payload.property_id] = payload;
                    updateUserSpecificInternetService(null, payload.property_id);
                }
            } else if (dataType === 'trash_status') { // Full update
                updateTrashModule(payload);
            } else if (dataType === 'trash_bin_status') { // Single bin update
                updateTrashBinDisplay(payload); // { binId: {load, capacity}}
            } else if (dataType === 'trash_illegal_dump_update') { // Single dump site update
                updateIllegalDumpDisplay(payload); // { id, isActive, coords }
            } else if (dataType === 'admin_status_update') {
                checkAdminPermissions(payload.isAdmin);
            }
        } else if (type === "SHOW_NOTIFICATION") {
            console.log("NUI Notification:", event.data.message);
            statusBar.textContent = event.data.message;
        }
    });

    function checkAdminPermissions(isAdmin) {
        console.log("Is Admin:", isAdmin);
        adminControls.forEach(control => control.classList.toggle('hidden', !isAdmin));
    }

    function updateAllModules(data) {
        if (data.power) updatePowerModule(data.power);
        if (data.water) updateWaterModule(data.water);
        if (data.internet && data.internet.hubs) updateInternetModule(data.internet.hubs);

        if (data.config) {
            populateInternetTiers(document.getElementById('admin-internet-tier-select'), data.config.Internet?.ServiceTiers);
            populateAdminSelect(powerZoneSelect, data.config.Power?.Zones, 'Select Power Zone');
            populateAdminSelect(document.getElementById('internet-hub-select'), data.config.Internet?.Hubs, 'Select Internet Hub');
        }

        // This assumes server sends a list of properties the player owns/manages.
        // For QBCore, this would come from `exports['qb-houses']:GetOwnedHouses()` result processed server-side.
        const playerProperties = data.internet?.playerProperties || [
             // Mock if not provided by server. Server should send this based on framework integration.
            { property_id: 'mockprop1', label: 'My Mock House', address: '123 Fake St' },
            { property_id: 'mockprop2', label: 'My Other Mock Condo', address: '456 Main Ave' }
        ];
        updateUserPropertiesInternetDisplay(playerProperties, window.cachedConfigData.Internet.ServiceTiers);

        if (data.trash) updateTrashModule(data.trash);
        statusBar.textContent = 'All modules updated.';
    }

    function populateAdminSelect(selectElement, items, defaultOptionText) {
        if (!selectElement || !items) return;
        selectElement.innerHTML = `<option value="">${defaultOptionText}</option>`;
        if (Array.isArray(items)) {
             items.forEach(item => {
                const option = document.createElement('option');
                option.value = item.id;
                option.textContent = item.label || item.name;
                selectElement.appendChild(option);
            });
        } else if (typeof items === 'object') {
            for (const key in items) {
                const item = items[key];
                const option = document.createElement('option');
                option.value = key;
                option.textContent = item.label || key;
                selectElement.appendChild(option);
            }
        }
    }

    function updatePowerModule(powerData) {
        const listElement = document.getElementById('power-status-list');
        if (!listElement) return;

        if (Object.keys(powerData).length === 0 && listElement.innerHTML.includes('Loading')) {
            listElement.innerHTML = '<p class="text-gray-400">No power zone data available.</p>';
            return;
        }
        const pTag = listElement.querySelector('p.text-gray-400');
        if (pTag) pTag.remove();

        for (const zoneId in powerData) {
            const zone = powerData[zoneId];
            let item = document.getElementById(`powerzone-${zoneId}`);
            if (!item) {
                item = document.createElement('div');
                item.id = `powerzone-${zoneId}`;
                item.className = 'status-item flex justify-between items-center';
                listElement.appendChild(item);
            }
            item.innerHTML = `
                <span>
                    <i class="fas fa-lightbulb mr-2 ${zone.isBlackout ? 'text-gray-500' : 'text-yellow-400'}"></i>
                    ${zone.label || zoneId}
                </span>
                <span class="status-indicator ${zone.isBlackout ? 'status-offline' : 'status-online'}"></span>
            `;
        }
    }

    function updateWaterModule(waterData) {
        const listElement = document.getElementById('water-status-list');
        if (!listElement) return;
        listElement.innerHTML = '';

        if (waterData.sources && Object.keys(waterData.sources).length > 0) {
            let sourcesHTML = '<h4 class="font-semibold mb-1 text-sm text-blue-200">Water Sources:</h4>';
            for (const sourceId in waterData.sources) {
                const source = waterData.sources[sourceId];
                const percentage = source.percentage !== undefined ? source.percentage : (source.currentLevel / source.capacity) * 100;
                const isLow = percentage < (source.alertThreshold * 100 || 25);
                sourcesHTML += `
                    <div class="status-item">
                        <i class="fas fa-database mr-2 ${isLow ? 'text-red-400' : 'text-blue-300'}"></i>
                        ${source.label || sourceId}:
                        <span class="font-medium ${isLow ? 'text-red-300' : 'text-gray-100'}">${percentage.toFixed(1)}%</span>
                        ${isLow ? '<span class="text-red-400 ml-2 font-semibold">(LOW)</span>' : ''}
                    </div>`;
            }
            listElement.innerHTML += sourcesHTML;
        } else {
            listElement.innerHTML += '<p class="text-gray-400">No water source data available.</p>';
        }

        listElement.innerHTML += '<h4 class="font-semibold mt-3 mb-1 text-sm text-orange-300">Active Leaks:</h4>';
        const leaksContainer = document.createElement('div');
        leaksContainer.id = 'active-leaks-list';
        listElement.appendChild(leaksContainer);

        if (waterData.leaks && waterData.leaks.length > 0) {
            waterData.leaks.forEach(leak => addLeakToUI(leak));
        } else {
             leaksContainer.innerHTML = '<p class="text-gray-400 mt-1">No active water leaks.</p>';
        }
    }

    function addLeakToUI(leak) {
        const leaksList = document.getElementById('active-leaks-list');
        if (!leaksList) return;
        const existingLeakElement = document.getElementById(`leak-${leak.id}`);
        if (existingLeakElement) existingLeakElement.remove();

        if (leak.isLeaking === false) {
             if (!leaksList.querySelector('.status-item')) {
                leaksList.innerHTML = '<p class="text-gray-400 mt-1">No active water leaks.</p>';
            }
            return;
        }
        const noLeaksMessage = leaksList.querySelector('p.text-gray-400');
        if (noLeaksMessage) noLeaksMessage.remove();

        const item = document.createElement('div');
        item.id = `leak-${leak.id}`;
        item.className = 'status-item text-orange-400';
        item.innerHTML = `<i class="fas fa-tint-slash mr-2"></i> Leak <strong>${leak.id}</strong> detected ${leak.locationDescription || 'in an unknown location'}`;
        leaksList.appendChild(item);
    }

    function updateWaterLeakStatus(leakData) {
        const leaksList = document.getElementById('active-leaks-list');
        if (!leaksList) {
            console.error("Could not find #active-leaks-list to update leak status.");
            postNuiMessage('user:requestFullWaterStatus');
            return;
        }
        addLeakToUI(leakData);
    }

    function updateInternetModule(hubsData) {
        const hubsListElement = document.getElementById('internet-hubs-status-list');
        if (!hubsListElement) return;

        const pTag = hubsListElement.querySelector('p.text-gray-400');
        if (pTag) pTag.remove();

        if (Object.keys(hubsData).length === 0 && hubsListElement.childElementCount === 1) {
            hubsListElement.innerHTML += '<p class="text-gray-400">No internet hub data available.</p>';
            return;
        }

        for (const hubId in hubsData) {
            const hub = hubsData[hubId];
            let item = document.getElementById(`hub-${hubId}`);
            if (!item) {
                item = document.createElement('div');
                item.id = `hub-${hubId}`;
                item.className = 'status-item flex justify-between items-center text-sm';
                hubsListElement.appendChild(item);
            }
            item.innerHTML = `
                <span>
                    <i class="fas fa-network-wired mr-2 ${hub.isDown ? 'text-gray-500' : 'text-green-400'}"></i>
                    ${hub.label || hubId} (Conn: ${hub.cc || hub.currentConnections || 0}/${hub.mc || hub.maxConnections || 'N/A'})
                </span>
                <span class="status-indicator ${hub.isDown ? 'status-offline' : 'status-online'}"></span>`;
        }
    }

    function updateUserPropertiesInternetDisplay(properties, serviceTiersConfig) {
        const servicesListElement = document.getElementById('user-internet-services-list');
        if (!servicesListElement) return;
        servicesListElement.innerHTML = '<h3 class="text-md font-semibold mb-1 text-gray-300">My Properties & Services:</h3>';

        if (!properties || properties.length === 0) {
            servicesListElement.innerHTML += '<p class="text-gray-400">You do not own any properties or property data is unavailable. (Note: Requires qb-houses integration or similar on server for property list)</p>';
            return;
        }

        properties.forEach(prop => { // prop expected to have at least: property_id, label, address
            const propertyId = prop.property_id;
            const propDiv = document.createElement('div');
            propDiv.className = 'property-internet-card p-3 bg-gray-700 rounded-md shadow';
            propDiv.id = `property-${propertyId}`;

            let statusHTML = `<h4 class="font-semibold text-gray-100">${prop.label || propertyId}</h4>`;
            if (prop.address) statusHTML += `<p class="text-xs text-gray-400 mb-1">${prop.address}</p>`;

            const currentSub = Internet.PlayerSubscriptions[propertyId];
            const pendingInstall = Internet.PendingInstallations[propertyId];

            if (currentSub && currentSub.is_active) {
                const tierConfig = serviceTiersConfig[currentSub.speed_tier];
                const hubIsDown = Internet.HubsState[currentSub.provider] ? Internet.HubsState[currentSub.provider].isDown : true;
                const effectiveServiceActive = !hubIsDown;
                statusHTML += `
                    <p class="text-sm ${effectiveServiceActive ? 'text-green-400' : 'text-red-400'}"><i class="fas ${effectiveServiceActive ? 'fa-check-circle' : 'fa-exclamation-triangle'} mr-1"></i>Active: ${tierConfig?.label || currentSub.speed_tier} (${tierConfig?.speed || 'N/A'})</p>
                    <p class="text-xs text-gray-400">Hub: ${currentSub.provider || 'N/A'} ${hubIsDown ? '<span class="text-red-500">(Hub Offline)</span>' : ''}</p>`;
            } else if (pendingInstall && pendingInstall.status === 'open') {
                 statusHTML += `<p class="text-sm text-yellow-400"><i class="fas fa-clock mr-1"></i>Installation Pending for ${pendingInstall.description.replace('Install ', '').replace(' at property: '+propertyId, '')}</p>`;
            } else {
                statusHTML += `<p class="text-sm text-yellow-400 mb-2"><i class="fas fa-times-circle mr-1"></i>No active internet service.</p>`;
                const selectId = `tier-select-${propertyId}`;
                statusHTML += `
                    <select id="${selectId}" class="bg-gray-800 border border-gray-600 rounded p-2 w-full mb-2 text-sm">
                        <option value="">Select Tier to Install</option>
                    </select>
                    <button data-property-id="${propertyId}" class="request-internet-install-btn bg-blue-500 hover:bg-blue-600 text-white py-2 px-3 rounded w-full text-sm">
                        Request Installation
                    </button>`;
            }
            propDiv.innerHTML = statusHTML;
            servicesListElement.appendChild(propDiv);

            if ((!currentSub || !currentSub.is_active) && (!pendingInstall || pendingInstall.status !== 'open')) {
                const tierSelect = document.getElementById(`tier-select-${propertyId}`);
                if (tierSelect) {
                    populateInternetTiers(tierSelect, serviceTiersConfig || window.cachedConfigData.Internet.ServiceTiers);
                    const installButton = propDiv.querySelector('.request-internet-install-btn');
                    if (installButton) {
                        installButton.addEventListener('click', handleRequestInstallationClick);
                    }
                }
            }
        });
    }

    function handleRequestInstallationClick(event) {
        const propertyId = event.target.dataset.propertyId;
        const tierSelect = document.getElementById(`tier-select-${propertyId}`);
        const selectedTier = tierSelect.value;
        if (selectedTier && propertyId) {
            postNuiMessage('user:requestInternetInstall', { tierId: selectedTier, propertyId: propertyId });
            statusBar.textContent = `Requesting installation for property ${propertyId}...`;
        } else if (!selectedTier){
            statusBar.textContent = 'Please select an internet tier first.';
        } else {
            statusBar.textContent = 'Property ID missing for installation request.';
        }
    }

    function updateUserSpecificInternetService(serviceData, propertyId) {
        if (!propertyId && serviceData && serviceData.property_id) {
            propertyId = serviceData.property_id;
        }
        if (!propertyId) {
            console.warn("updateUserSpecificInternetService missing propertyId.", serviceData);
            return;
        }

        if (serviceData) { // serviceData is the new subscription object from server
            Internet.PlayerSubscriptions[propertyId] = serviceData;
            if (serviceData.is_active && Internet.PendingInstallations[propertyId]) {
                delete Internet.PendingInstallations[propertyId];
            }
        } else {
            delete Internet.PlayerSubscriptions[propertyId];
        }

        const propDiv = document.getElementById(`property-${propertyId}`);
        if (!propDiv) {
             // If the property card isn't there, it means the initial list of properties hasn't been rendered yet,
            // or this property wasn't in it. The next full 'initial_load' or manual refresh should pick it up.
            console.warn(`Property card for ${propertyId} not found to update service. It will update on next full property list refresh.`);
            return;
        }

        const existingLabel = propDiv.querySelector('h4')?.textContent || propertyId;
        const existingAddress = propDiv.querySelector('p.text-xs.text-gray-400')?.textContent || '';

        // Create a temporary property object to re-render its card
        const tempPropertyData = {
            property_id: propertyId,
            label: existingLabel,
            address: existingAddress
            // The internet status will be picked from Internet.PlayerSubscriptions & Internet.PendingInstallations inside the render path
        };

        // To re-render just this one card:
        const newCard = document.createElement('div'); // Create a dummy parent
        updateUserPropertiesInternetDisplay([tempPropertyData], window.cachedConfigData.Internet.ServiceTiers); // This function expects an array
        const updatedCardContent = document.getElementById(`property-${propertyId}`); // Find the newly rendered card

        if(updatedCardContent) { // Check if the card was actually re-rendered
            propDiv.replaceWith(updatedCardContent.cloneNode(true)); // Replace old with new
             // Re-attach listener if install button is present on the new card
            const installButton = document.getElementById(`property-${propertyId}`)?.querySelector('.request-internet-install-btn');
            if (installButton) {
                installButton.addEventListener('click', handleRequestInstallationClick);
            }
        } else {
            // Fallback: If single re-render is complex, request full property list update from server
            // This might be needed if the property wasn't in the initial list.
            // postNuiMessage('user:requestFullPropertiesList'); // Example: ask server to resend properties for this user
            console.warn("Failed to re-render single property card, consider full refresh or ensure property was in initial list.");
        }
    }

    function populateInternetTiers(selectElement, tiers) {
        if (!selectElement || !tiers) return;
        selectElement.innerHTML = '<option value="">Select Tier to Install</option>';
        for (const tierKey in tiers) {
            const tier = tiers[tierKey];
            const option = document.createElement('option');
            option.value = tierKey;
            option.textContent = `${tier.label} (${tier.speed}) - $${tier.price}`;
            selectElement.appendChild(option);
        }
    }

    function updateTrashModule(trashData) { // trashData = { public_bins, large_dumpsters, illegal_dumps }
        const listElement = document.getElementById('trash-status-list');
        if (!listElement) return;
        listElement.innerHTML = ''; // Clear previous full status

        let contentHTML = '';

        // Public Bins
        contentHTML += '<h4 class="font-semibold mb-1 text-sm text-gray-300">Public Bins:</h4>';
        const binsContainerId = 'public-bins-status-list';
        contentHTML += `<div id="${binsContainerId}" class="space-y-1 pl-2">`;
        if (trashData.public_bins && Object.keys(trashData.public_bins).length > 0) {
            for (const binId in trashData.public_bins) {
                contentHTML += renderTrashBinHTML(trashData.public_bins[binId]);
            }
        } else {
            contentHTML += '<p class="text-xs text-gray-400">No public bin data.</p>';
        }
        contentHTML += '</div>';

        // Large Dumpsters (similar rendering)
        contentHTML += '<h4 class="font-semibold mt-2 mb-1 text-sm text-gray-300">Large Dumpsters:</h4>';
        const dumpstersContainerId = 'large-dumpsters-status-list';
        contentHTML += `<div id="${dumpstersContainerId}" class="space-y-1 pl-2">`;
        if (trashData.large_dumpsters && Object.keys(trashData.large_dumpsters).length > 0) {
            for (const dumpsterId in trashData.large_dumpsters) {
                 contentHTML += renderTrashBinHTML(trashData.large_dumpsters[dumpsterId]); // Assuming same structure
            }
        } else {
            contentHTML += '<p class="text-xs text-gray-400">No large dumpster data.</p>';
        }
        contentHTML += '</div>';

        // Illegal Dumps
        contentHTML += '<h4 class="font-semibold mt-2 mb-1 text-sm text-red-400">Illegal Dumping Sites:</h4>';
        const illegalDumpsContainerId = 'illegal-dumps-status-list';
        contentHTML += `<div id="${illegalDumpsContainerId}" class="space-y-1 pl-2">`;
        if (trashData.illegal_dumps && trashData.illegal_dumps.length > 0) {
            trashData.illegal_dumps.forEach(dump => {
                contentHTML += renderIllegalDumpHTML(dump);
            });
        } else {
            contentHTML += '<p class="text-xs text-gray-400">No active illegal dump sites.</p>';
        }
        contentHTML += '</div>';

        listElement.innerHTML = contentHTML;
    }

    function renderTrashBinHTML(binData) {
        const percentage = binData.capacity > 0 ? (binData.load / binData.capacity) * 100 : 0;
        let loadColor = 'text-green-400';
        if (percentage > 85) loadColor = 'text-red-400';
        else if (percentage > 60) loadColor = 'text-yellow-400';
        return `
            <div id="trashbin-${binData.id}" class="status-item text-xs">
                <i class="fas fa-trash-alt mr-1 ${loadColor}"></i>
                ${binData.label || binData.id}: <span class="${loadColor} font-medium">${percentage.toFixed(0)}% Full</span>
                (Load: ${binData.load}/${binData.capacity})
            </div>`;
    }

    function renderIllegalDumpHTML(dumpData) {
         return `
            <div id="illegaldump-${dumpData.id}" class="status-item text-xs text-red-300">
                <i class="fas fa-dumpster-fire mr-1"></i>
                Dump ID: ${dumpData.id} (Items: ${dumpData.items ? dumpData.items.length : 'N/A'})
                ${dumpData.coords ? `near (${dumpData.coords.x.toFixed(0)}, ${dumpData.coords.y.toFixed(0)})` : ''}
            </div>`;
    }

    function updateTrashBinDisplay(binUpdateData) { // binUpdateData = { binId: {load, capacity, label?, id?} }
        for (const binId in binUpdateData) {
            const data = binUpdateData[binId];
            const binElement = document.getElementById(`trashbin-${binId}`);
            const fullBinData = { // Construct full object for render function
                id: data.id || binId,
                label: data.label || binId, // Try to get label from existing if not in update
                load: data.load,
                capacity: data.capacity
            };
            if (binElement) {
                binElement.outerHTML = renderTrashBinHTML(fullBinData);
            } else { // Bin might not have been in initial list (e.g. if list was empty)
                // Try to find appropriate container and append
                const publicBinsList = document.getElementById('public-bins-status-list');
                const dumpstersList = document.getElementById('large-dumpsters-status-list');
                // This logic might need refinement if IDs don't clearly distinguish type
                if (publicBinsList && binId.startsWith("bin@")) publicBinsList.innerHTML += renderTrashBinHTML(fullBinData);
                else if (dumpstersList && binId.startsWith("dumpster@")) dumpstersList.innerHTML += renderTrashBinHTML(fullBinData);

            }
        }
    }

    function updateIllegalDumpDisplay(dumpUpdateData) { // dumpUpdateData = { id, isActive, coords, items? }
        const listElement = document.getElementById('illegal-dumps-status-list');
        if (!listElement) return;

        const existingDumpElement = document.getElementById(`illegaldump-${dumpUpdateData.id}`);
        if (existingDumpElement) existingDumpElement.remove();

        if (dumpUpdateData.isActive) {
            const noDumpsMessage = listElement.querySelector('p.text-xs.text-gray-400');
            if (noDumpsMessage) noDumpsMessage.remove();
            listElement.innerHTML += renderIllegalDumpHTML(dumpUpdateData);
        } else {
            if (!listElement.querySelector('.status-item')) {
                listElement.innerHTML = '<p class="text-xs text-gray-400">No active illegal dump sites.</p>';
            }
        }
    }


    // --- Event Listeners for UI interactions ---
    if (forceBlackoutBtn && powerZoneSelect) {
        forceBlackoutBtn.addEventListener('click', () => {
            const selectedZone = powerZoneSelect.value;
            if (selectedZone) {
                postNuiMessage('admin:forceBlackout', { zoneId: selectedZone });
                statusBar.textContent = `Attempting to force blackout in ${selectedZone}...`;
            } else {
                statusBar.textContent = 'Please select a power zone first.';
            }
        });
    }

    if (repairPowerBtn && powerZoneSelect) {
        repairPowerBtn.addEventListener('click', () => {
            const selectedZone = powerZoneSelect.value;
            if (selectedZone) {
                postNuiMessage('admin:repairPowerZone', { zoneId: selectedZone });
                statusBar.textContent = `Attempting to repair power zone ${selectedZone}...`;
            } else {
                statusBar.textContent = 'Please select a power zone first.';
            }
        });
    }

    // Note: User request for internet install is handled by dynamically added buttons

    if (reportDumpingBtn) {
        reportDumpingBtn.addEventListener('click', () => {
            postNuiMessage('user:reportIllegalDumping');
            statusBar.textContent = 'Reporting illegal dumping at current location...';
        });
    }

    const forceInternetOutageBtn = document.getElementById('force-internet-outage-btn');
    const internetHubSelect = document.getElementById('internet-hub-select');
    if (forceInternetOutageBtn && internetHubSelect) {
        forceInternetOutageBtn.addEventListener('click', () => {
            const selectedHub = internetHubSelect.value;
            if (selectedHub) {
                postNuiMessage('admin:forceInternetOutage', { hubId: selectedHub });
                statusBar.textContent = `Attempting to force outage for hub ${selectedHub}...`;
            } else {
                statusBar.textContent = 'Please select an internet hub first.';
            }
        });
    }

    const forceWaterLeakBtn = document.getElementById('force-water-leak-btn');
    if (forceWaterLeakBtn) {
        forceWaterLeakBtn.addEventListener('click', () => {
            postNuiMessage('admin:forceWaterLeak');
            statusBar.textContent = 'Attempting to force a random water leak...';
        });
    }

    const spawnTrashBtn = document.getElementById('spawn-trash-btn');
    if (spawnTrashBtn) {
        spawnTrashBtn.addEventListener('click', () => {
            postNuiMessage('admin:spawnTrash');
            statusBar.textContent = 'Attempting to spawn trash (admin)...';
        });
    }

    // Admin request for internet installation
    const adminRequestInstallBtn = document.getElementById('admin-request-internet-install-btn'); // Assuming you add this button
    const adminPropertyIdInput = document.getElementById('admin-property-id-input');
    const adminInternetTierSelect = document.getElementById('admin-internet-tier-select');

    if(adminRequestInstallBtn && adminPropertyIdInput && adminInternetTierSelect) {
        adminRequestInstallBtn.addEventListener('click', () => {
            const propertyId = adminPropertyIdInput.value;
            const tierId = adminInternetTierSelect.value;
            if(propertyId && tierId) {
                postNuiMessage('admin:requestInternetInstall', { propertyId, tierId }); // Server needs to handle this admin version
                statusBar.textContent = `Admin: Requesting install for ${propertyId}, tier ${tierId}`;
            } else {
                statusBar.textContent = 'Admin: Property ID and Tier required for install request.';
            }
        });
    }


    postNuiMessage('NUI_READY');
    statusBar.textContent = 'Dashboard loaded. Waiting for initial data...';

    if (!window.GetParentResourceName) {
        console.warn("Running in browser mode. NUI messages will be logged.");
        setTimeout(() => {
            checkAdminPermissions(true);
            const mockConfig = {
                Internet: {
                    ServiceTiers: {
                        basic: {label: "Basic ADSL", speed: "25/5 Mbps", price: 75},
                        premium: {label: "Premium Fiber", speed: "500/100 Mbps", price: 200}
                    },
                    Hubs: { 'LS_MainExchange': {label: 'LS Main'}, 'PaletoBayHub': {label: 'Paleto Hub'} }
                },
                Power: { Zones: { 'Downtown': {label: 'Downtown'}, 'Vinewood': {label: 'Vinewood'} } },
            };
            window.cachedConfigData = mockConfig; // Populate cache for mock

            const mockInitialData = {
                isAdmin: true,
                config: mockConfig,
                power: {
                    'Downtown': { label: "Downtown Power Grid", isBlackout: false },
                    'Vinewood': { label: "Vinewood Hills Power", isBlackout: true }
                },
                water: {
                    sources: { 'LandActReservoir': { label: "Land Act Reservoir", currentLevel: 750000, capacity: 1000000, alertThreshold: 0.25 } },
                    leaks: [ {id: 'leak1', locationDescription: 'near Legion Square', isLeaking: true} ]
                },
                internet: {
                    hubs: {
                        'LS_MainExchange': { label: "LS Main Exchange", isDown: false, cc: 120, mc: 5000 },
                        'PaletoBayHub': { label: "Paleto Bay Hub", isDown: true, cc: 10, mc: 500 }
                    },
                    playerProperties: [ // Server should send this list based on player's owned houses
                        { property_id: 'prop_123', label: 'My Apartment (123)', address: 'Vinewood Ave' },
                        { property_id: 'prop_456', label: 'Beach House (456)', address: 'Vespucci Beach' }
                    ],
                    // Individual subscriptions will be populated into Internet.PlayerSubscriptions by mock server events later
                },
                trash: { overallStatus: "Collection services operating normally.", illegalDumpingAlerts: [] }
            };
            // Simulate server sending initial data
            window.dispatchEvent(new MessageEvent('message', { data: { type: 'UPDATE_DATA', dataType: 'initial_load', payload: mockInitialData } }));

            // Simulate receiving specific user service data after initial load
            setTimeout(() => {
                 Internet.PlayerSubscriptions['prop_456'] = { property_id: 'prop_456', citizenid: 'mockcitizen', provider: 'LS_MainExchange', speed_tier: 'premium', is_active: true, last_payment: Date.now()};
                 updateUserSpecificInternetService(Internet.PlayerSubscriptions['prop_456'], 'prop_456');

                 Internet.PendingInstallations['prop_123'] = {ticket_id: 1, type:'internet_install', property_id:'prop_123', citizenid:'mockcitizen', description:'Install Basic ADSL at property: prop_123', status:'open'};
                 updateUserSpecificInternetService(null, 'prop_123'); // Trigger re-render for pending
            }, 500);

        }, 1000);
    }
});
