document.addEventListener('DOMContentLoaded', () => {
    const tabletContainer = document.querySelector('body');
    const closeButton = document.getElementById('close-tablet-btn');
    const statusBar = document.getElementById('status-bar');

    const adminControls = document.querySelectorAll('.admin-controls');
    const forceBlackoutBtn = document.getElementById('force-blackout-btn');
    const repairPowerBtn = document.getElementById('repair-power-btn');
    const powerZoneSelect = document.getElementById('power-zone-select');

    const reportDumpingBtn = document.getElementById('report-dumping-btn');

    // Local NUI cache for internet related data
    const Internet = {
        PlayerSubscriptions: {}, // { property_id: { citizenid, property_id, provider, speed_tier, is_active, last_payment } }
        PendingInstallations: {}, // { property_id: { ticket_id, type, property_id, citizenid, description, status, speed_tier? } }
        HubsState: {} // { hub_id: { label, isDown, currentConnections, maxConnections, ... } }
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
        // Request fresh full data when NUI is shown, to get latest property list etc.
        postNuiMessage('NUI_READY'); // NUI_READY effectively asks for initial_load from server
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
                if (payload.config?.Internet?.ServiceTiers) {
                    window.cachedConfigData.Internet.ServiceTiers = payload.config.Internet.ServiceTiers;
                }
                Internet.HubsState = payload.internet?.hubs || {};
                Internet.PlayerSubscriptions = payload.internet?.subscriptions || {};
                Internet.PendingInstallations = payload.internet?.pendingInstallations || {};
                updateAllModules(payload);
                checkAdminPermissions(payload.isAdmin);
            } else if (dataType === 'power_status') {
                updatePowerModule(payload);
            } else if (dataType === 'water_status') {
                updateWaterModule(payload);
            } else if (dataType === 'water_leak_update') {
                updateWaterLeakStatus(payload);
            } else if (dataType === 'internet_status') {
                if (payload.hubs) {
                    Internet.HubsState = payload.hubs;
                    updateInternetModule(payload.hubs);
                }
                if (payload.userService && payload.userService.property_id) {
                    Internet.PlayerSubscriptions[payload.userService.property_id] = payload.userService;
                    updateUserSpecificInternetService(payload.userService, payload.userService.property_id);
                } else if (payload.userService) {
                     console.log("General userService update (no propertyId, or for a non-listed context):", payload.userService);
                }
                if (payload.hubs && document.getElementById('user-internet-services-list')) {
                     const currentProps = Array.from(document.querySelectorAll('.property-internet-card')).map(el => ({
                        property_id: el.id.replace('property-', ''),
                        label: el.querySelector('h4')?.textContent || el.id.replace('property-', ''),
                        address: el.querySelector('p.text-xs.text-gray-400')?.textContent || ''
                    }));
                    updateUserPropertiesInternetDisplay(currentProps, window.cachedConfigData.Internet.ServiceTiers);
                }
            } else if (dataType === 'internet_hub_status') {
                for(const hubId in payload){
                    Internet.HubsState[hubId] = {...(Internet.HubsState[hubId] || {}), ...payload[hubId]};
                }
                updateInternetModule(payload);
                 const currentProps = Array.from(document.querySelectorAll('.property-internet-card')).map(el => ({
                    property_id: el.id.replace('property-', ''),
                    label: el.querySelector('h4')?.textContent || el.id.replace('property-', ''),
                    address: el.querySelector('p.text-xs.text-gray-400')?.textContent || ''
                }));
                updateUserPropertiesInternetDisplay(currentProps, window.cachedConfigData.Internet.ServiceTiers);
            } else if (dataType === 'internet_user_service') {
                if (payload && payload.property_id) {
                    Internet.PlayerSubscriptions[payload.property_id] = payload;
                    if (payload.is_active && Internet.PendingInstallations[payload.property_id]) {
                        delete Internet.PendingInstallations[payload.property_id];
                    }
                    updateUserSpecificInternetService(payload, payload.property_id);
                }
            } else if (dataType === 'internet_pending_install_update') {
                if(payload && payload.property_id) {
                    Internet.PendingInstallations[payload.property_id] = payload;
                    updateUserSpecificInternetService(null, payload.property_id);
                }
            } else if (dataType === 'trash_status') {
                updateTrashModule(payload);
            } else if (dataType === 'trash_bin_status') {
                updateTrashBinDisplay(payload);
            } else if (dataType === 'trash_illegal_dump_update') {
                updateIllegalDumpDisplay(payload);
            } else if (dataType === 'admin_status_update') {
                checkAdminPermissions(payload.isAdmin);
            }
        } else if (type === "SHOW_NOTIFICATION") {
            console.log("NUI Notification:", event.data.message);
            statusBar.textContent = event.data.message;
        }
    });

    function checkAdminPermissions(isAdmin) {
        console.log("NUI: Admin status is", isAdmin);
        adminControls.forEach(control => control.classList.toggle('hidden', !isAdmin));
    }

    function updateAllModules(data) {
        if (data.power) updatePowerModule(data.power);
        if (data.water) updateWaterModule(data.water);
        if (data.internet?.hubs) updateInternetModule(data.internet.hubs);

        if (data.config) {
            if(data.config.Internet?.ServiceTiers) window.cachedConfigData.Internet.ServiceTiers = data.config.Internet.ServiceTiers;
            populateInternetTiers(document.getElementById('admin-internet-tier-select'), data.config.Internet?.ServiceTiers);
            populateAdminSelect(powerZoneSelect, data.config.Power?.Zones, 'Select Power Zone');
            populateAdminSelect(document.getElementById('internet-hub-select'), data.config.Internet?.Hubs, 'Select Internet Hub');
        }

        const playerProperties = data.internet?.playerProperties || [];
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

        const pTag = listElement.querySelector('p.text-gray-400');
        if (Object.keys(powerData).length === 0 && pTag && pTag.textContent.includes('Loading')) {
            listElement.innerHTML = '<p class="text-gray-400">No power zone data available.</p>'; return;
        }
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
                <span><i class="fas fa-lightbulb mr-2 ${zone.isBlackout ? 'text-gray-500' : 'text-yellow-400'}"></i>${zone.label||zoneId}</span>
                <span class="status-indicator ${zone.isBlackout ? 'status-offline' : 'status-online'}"></span>`;
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
                sourcesHTML += `<div class="status-item"><i class="fas fa-database mr-2 ${isLow ? 'text-red-400':'text-blue-300'}"></i>${source.label||sourceId}: <span class="font-medium ${isLow ? 'text-red-300':'text-gray-100'}">${percentage.toFixed(1)}%</span>${isLow ? '<span class="text-red-400 ml-2 font-semibold">(LOW)</span>':''}</div>`;
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
             if (!leaksList.querySelector('.status-item')) leaksList.innerHTML = '<p class="text-gray-400 mt-1">No active water leaks.</p>';
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
        if (!leaksList) { console.error("Could not find #active-leaks-list to update leak status."); postNuiMessage('user:requestFullWaterStatus'); return; }
        addLeakToUI(leakData);
    }

    function updateInternetModule(hubsData) { // hubsData is { hubId: data, ... }
        const hubsListElement = document.getElementById('internet-hubs-status-list');
        if (!hubsListElement) return;
        const pTag = hubsListElement.querySelector('p.text-gray-400');
        if (pTag) pTag.remove();
        if (Object.keys(hubsData).length === 0 && hubsListElement.childElementCount === 1) {
            hubsListElement.innerHTML += '<p class="text-gray-400">No internet hub data available.</p>'; return;
        }
        for (const hubId in hubsData) {
            const hub = hubsData[hubId];
            let item = document.getElementById(`hub-${hubId}`);
            if (!item) {
                item = document.createElement('div'); item.id = `hub-${hubId}`;
                item.className = 'status-item flex justify-between items-center text-sm';
                hubsListElement.appendChild(item);
            }
            const currentConns = hub.cc ?? hub.currentConnections ?? 0;
            const maxConns = hub.mc ?? hub.maxConnections ?? 'N/A';
            item.innerHTML = `<span><i class="fas fa-network-wired mr-2 ${hub.isDown?'text-gray-500':'text-green-400'}"></i>${hub.label||hubId} (Conn: ${currentConns}/${maxConns})</span><span class="status-indicator ${hub.isDown?'status-offline':'status-online'}"></span>`;
        }
    }

    function updateUserPropertiesInternetDisplay(properties, serviceTiersConfig) {
        const servicesListElement = document.getElementById('user-internet-services-list');
        if (!servicesListElement) return;
        servicesListElement.innerHTML = '<h3 class="text-md font-semibold mb-1 text-gray-300">My Properties & Services:</h3>';

        if (!properties || properties.length === 0) {
            servicesListElement.innerHTML += '<p class="text-gray-400">You do not own any properties or property data is unavailable. (Note: Requires housing script integration on server for property list)</p>';
            return;
        }

        properties.forEach(prop => {
            const propertyId = prop.property_id;
            const propDiv = document.createElement('div');
            propDiv.className = 'property-internet-card p-3 bg-gray-700 rounded-md shadow';
            propDiv.id = `property-${propertyId}`;

            let contentHTML = `<h4 class="font-semibold text-gray-100">${prop.label || propertyId}</h4>`;
            if (prop.address) contentHTML += `<p class="text-xs text-gray-400 mb-1">${prop.address}</p>`;

            const currentSub = Internet.PlayerSubscriptions[propertyId];
            const pendingInstall = Internet.PendingInstallations[propertyId];
            const allServiceTiers = serviceTiersConfig || window.cachedConfigData.Internet.ServiceTiers;

            if (currentSub && currentSub.is_active) {
                const tierConfig = allServiceTiers[currentSub.speed_tier];
                const hubIsDown = Internet.HubsState[currentSub.provider] ? Internet.HubsState[currentSub.provider].isDown : false;
                const effectiveServiceActive = !hubIsDown;
                contentHTML += `<p class="text-sm ${effectiveServiceActive ? 'text-green-400' : 'text-red-400'}"><i class="fas ${effectiveServiceActive ? 'fa-check-circle' : 'fa-exclamation-triangle'} mr-1"></i>Current Plan: <strong>${tierConfig?.label || currentSub.speed_tier}</strong> (${tierConfig?.speed || 'N/A'}) ${!effectiveServiceActive ? '<span class="font-semibold">(Service Interrupted)</span>' : ''}</p>`;
                if(effectiveServiceActive) contentHTML += `<p class="text-xs text-gray-400">Hub: ${currentSub.provider || 'N/A'} ${hubIsDown ? '<span class="text-red-500 font-bold">(Hub Offline)</span>' : ''}</p>`;

                const upgradeSelectId = `upgrade-tier-select-${propertyId}`;
                contentHTML += `<div class="mt-2"><select id="${upgradeSelectId}" class="bg-gray-800 border border-gray-600 rounded p-2 w-full mb-1 text-sm"><option value="">Select New Tier to Upgrade</option></select><button data-property-id="${propertyId}" data-action="upgrade" class="request-internet-action-btn bg-yellow-500 hover:bg-yellow-600 text-white py-2 px-3 rounded w-full text-sm">Request Upgrade</button></div>`;
            } else if (pendingInstall && pendingInstall.status === 'open') {
                 let pendingTierLabel = "Unknown Tier";
                 const pendingSpeedTier = pendingInstall.speed_tier || (pendingInstall.description ? (pendingInstall.description.match(/Install (.*?) at/) || [])[1] : null);
                 if (pendingSpeedTier && allServiceTiers[pendingSpeedTier]) {
                     pendingTierLabel = allServiceTiers[pendingSpeedTier].label;
                 } else if (pendingInstall.description) {
                     pendingTierLabel = pendingInstall.description.replace('Install ', '').split(' at property:')[0];
                 }
                 contentHTML += `<p class="text-sm text-yellow-400"><i class="fas fa-clock mr-1"></i>Installation Pending for ${pendingTierLabel}</p>`;
            } else {
                contentHTML += `<p class="text-sm text-yellow-400 mb-2"><i class="fas fa-times-circle mr-1"></i>No active internet service.</p>`;
                const selectId = `tier-select-${propertyId}`;
                contentHTML += `<select id="${selectId}" class="bg-gray-800 border border-gray-600 rounded p-2 w-full mb-2 text-sm"><option value="">Select Tier to Install</option></select><button data-property-id="${propertyId}" data-action="install" class="request-internet-action-btn bg-blue-500 hover:bg-blue-600 text-white py-2 px-3 rounded w-full text-sm">Request Installation</button>`;
            }
            propDiv.innerHTML = contentHTML;
            servicesListElement.appendChild(propDiv);

            if (currentSub && currentSub.is_active) {
                const upgradeTierSelect = document.getElementById(`upgrade-tier-select-${propertyId}`);
                if (upgradeTierSelect) populateInternetTiers(upgradeTierSelect, allServiceTiers, currentSub.speed_tier);
            } else if ((!currentSub || !currentSub.is_active) && (!pendingInstall || pendingInstall.status !== 'open')) {
                const tierSelect = document.getElementById(`tier-select-${propertyId}`);
                if (tierSelect) populateInternetTiers(tierSelect, allServiceTiers);
            }
            propDiv.querySelectorAll('.request-internet-action-btn').forEach(btn => btn.addEventListener('click', handleInternetActionClick));
        });
    }

    function handleInternetActionClick(event) {
        const propertyId = event.target.dataset.propertyId;
        const action = event.target.dataset.action;
        const tierSelectId = action === 'install' ? `tier-select-${propertyId}` : `upgrade-tier-select-${propertyId}`;
        const tierSelect = document.getElementById(tierSelectId);
        const selectedTier = tierSelect.value;

        if (selectedTier && propertyId) {
            const eventName = action === 'install' ? 'user:requestInternetInstall' : 'user:requestInternetUpgrade';
            postNuiMessage(eventName, { tierId: selectedTier, propertyId: propertyId });
            statusBar.textContent = `Requesting ${action} for property ${propertyId}...`;
        } else if (!selectedTier){
            statusBar.textContent = `Please select a tier to ${action}.`;
        } else {
            statusBar.textContent = 'Property ID missing for request.';
        }
    }

    function updateUserSpecificInternetService(serviceData, propertyId) {
        if (!propertyId && serviceData && serviceData.property_id) propertyId = serviceData.property_id;
        if (!propertyId) { console.warn("updateUserSpecificInternetService missing propertyId.", serviceData); return; }

        if (serviceData) {
            Internet.PlayerSubscriptions[propertyId] = serviceData;
            if (serviceData.is_active && Internet.PendingInstallations[propertyId]) {
                delete Internet.PendingInstallations[propertyId];
            }
        } else {
            delete Internet.PlayerSubscriptions[propertyId];
        }

        const propDiv = document.getElementById(`property-${propertyId}`);
        if (!propDiv) {
            console.warn(`Property card for ${propertyId} not found to update service. A full refresh might be needed if property list was not loaded.`);
            return;
        }

        const existingLabel = propDiv.querySelector('h4')?.textContent || propertyId;
        const existingAddress = propDiv.querySelector('p.text-xs.text-gray-400')?.textContent || '';

        const tempPropertyData = {
            property_id: propertyId,
            label: existingLabel,
            address: existingAddress
        };

        const tempParent = document.createElement('div');
        const tempServicesList = { appendChild: (child) => tempParent.appendChild(child) };
        updateUserPropertiesInternetDisplay.call(tempServicesList, [tempPropertyData], window.cachedConfigData.Internet.ServiceTiers);

        const newCardRendered = tempParent.querySelector(`#property-${propertyId}`);
        if (newCardRendered) {
            propDiv.innerHTML = newCardRendered.innerHTML;
            const newCardInDom = document.getElementById(`property-${propertyId}`);
            if(newCardInDom) {
                newCardInDom.querySelectorAll('.request-internet-action-btn').forEach(btn => btn.addEventListener('click', handleInternetActionClick));
            }
        } else {
            console.warn("Failed to re-render single property card for update.", propertyId);
        }
    }

    function populateInternetTiers(selectElement, tiers, excludeTierKey = null) {
        if (!selectElement || !tiers) return;
        const currentValue = selectElement.value;
        selectElement.innerHTML = `<option value="">${excludeTierKey ? 'Select New Tier' : 'Select Tier'}</option>`;
        for (const tierKey in tiers) {
            if (tierKey === excludeTierKey && excludeTierKey !== null) continue;
            const tier = tiers[tierKey];
            const option = document.createElement('option');
            option.value = tierKey;
            option.textContent = `${tier.label} (${tier.speed}) - $${tier.price}`;
            selectElement.appendChild(option);
        }
        if (currentValue) selectElement.value = currentValue;
    }

    function updateTrashModule(trashData) {
        const listElement = document.getElementById('trash-status-list');
        if (!listElement) return;
        listElement.innerHTML = '';
        let contentHTML = '';
        contentHTML += '<h4 class="font-semibold mb-1 text-sm text-gray-300">Public Bins:</h4>';
        const binsContainerId = 'public-bins-status-list';
        contentHTML += `<div id="${binsContainerId}" class="space-y-1 pl-2">`;
        if (trashData.public_bins && Object.keys(trashData.public_bins).length > 0) {
            for (const binId in trashData.public_bins) contentHTML += renderTrashBinHTML(trashData.public_bins[binId]);
        } else contentHTML += '<p class="text-xs text-gray-400">No public bin data.</p>';
        contentHTML += '</div>';
        contentHTML += '<h4 class="font-semibold mt-2 mb-1 text-sm text-gray-300">Large Dumpsters:</h4>';
        const dumpstersContainerId = 'large-dumpsters-status-list';
        contentHTML += `<div id="${dumpstersContainerId}" class="space-y-1 pl-2">`;
        if (trashData.large_dumpsters && Object.keys(trashData.large_dumpsters).length > 0) {
            for (const dumpsterId in trashData.large_dumpsters) contentHTML += renderTrashBinHTML(trashData.large_dumpsters[dumpsterId]);
        } else contentHTML += '<p class="text-xs text-gray-400">No large dumpster data.</p>';
        contentHTML += '</div>';
        contentHTML += '<h4 class="font-semibold mt-2 mb-1 text-sm text-red-400">Illegal Dumping Sites:</h4>';
        const illegalDumpsContainerId = 'illegal-dumps-status-list';
        contentHTML += `<div id="${illegalDumpsContainerId}" class="space-y-1 pl-2">`;
        if (trashData.illegal_dumps && trashData.illegal_dumps.length > 0) {
            trashData.illegal_dumps.forEach(dump => contentHTML += renderIllegalDumpHTML(dump));
        } else contentHTML += '<p class="text-xs text-gray-400">No active illegal dump sites.</p>';
        contentHTML += '</div>';
        listElement.innerHTML = contentHTML;
    }

    function renderTrashBinHTML(binData) {
        const percentage = binData.capacity > 0 ? (binData.load / binData.capacity) * 100 : 0;
        let loadColor = 'text-green-400';
        if (percentage > 85) loadColor = 'text-red-400'; else if (percentage > 60) loadColor = 'text-yellow-400';
        return `<div id="trashbin-${binData.id}" class="status-item text-xs"><i class="fas fa-trash-alt mr-1 ${loadColor}"></i>${binData.label||binData.id}: <span class="${loadColor} font-medium">${percentage.toFixed(0)}% Full</span> (Load: ${binData.load}/${binData.capacity})</div>`;
    }

    function renderIllegalDumpHTML(dumpData) {
         return `<div id="illegaldump-${dumpData.id}" class="status-item text-xs text-red-300"><i class="fas fa-dumpster-fire mr-1"></i>Dump ID: ${dumpData.id} (Items: ${dumpData.items?.length||'N/A'}) ${dumpData.coords?`near (${dumpData.coords.x.toFixed(0)}, ${dumpData.coords.y.toFixed(0)})`:''}</div>`;
    }

    function updateTrashBinDisplay(binUpdateData) {
        for (const binId in binUpdateData) {
            const data = binUpdateData[binId];
            const binElement = document.getElementById(`trashbin-${binId}`);
            const fullBinData = {id:data.id||binId, label:data.label||binId, load:data.load, capacity:data.capacity};
            if (binElement) binElement.outerHTML = renderTrashBinHTML(fullBinData);
            else {
                const publicBinsList = document.getElementById('public-bins-status-list');
                const dumpstersList = document.getElementById('large-dumpsters-status-list');
                if (publicBinsList && (data.id || binId).toLowerCase().startsWith("bin")) publicBinsList.innerHTML += renderTrashBinHTML(fullBinData);
                else if (dumpstersList && (data.id || binId).toLowerCase().startsWith("dumpster")) dumpstersList.innerHTML += renderTrashBinHTML(fullBinData);
            }
        }
    }

    function updateIllegalDumpDisplay(dumpUpdateData) {
        const listElement = document.getElementById('illegal-dumps-status-list');
        if (!listElement) return;
        const existingDumpElement = document.getElementById(`illegaldump-${dumpUpdateData.id}`);
        if (existingDumpElement) existingDumpElement.remove();
        if (dumpUpdateData.isActive) {
            const noDumpsMessage = listElement.querySelector('p.text-xs.text-gray-400');
            if (noDumpsMessage) noDumpsMessage.remove();
            listElement.innerHTML += renderIllegalDumpHTML(dumpUpdateData);
        } else {
            if (!listElement.querySelector('.status-item')) listElement.innerHTML = '<p class="text-xs text-gray-400">No active illegal dump sites.</p>';
        }
    }

    if (forceBlackoutBtn && powerZoneSelect) {
        forceBlackoutBtn.addEventListener('click', () => {
            const selectedZone = powerZoneSelect.value;
            if (selectedZone) { postNuiMessage('admin:forceBlackout', { zoneId: selectedZone }); statusBar.textContent = `Forcing blackout: ${selectedZone}...`; }
            else { statusBar.textContent = 'Select power zone.'; }
        });
    }
    if (repairPowerBtn && powerZoneSelect) {
        repairPowerBtn.addEventListener('click', () => {
            const selectedZone = powerZoneSelect.value;
            if (selectedZone) { postNuiMessage('admin:repairPowerZone', { zoneId: selectedZone }); statusBar.textContent = `Repairing zone: ${selectedZone}...`; }
            else { statusBar.textContent = 'Select power zone.'; }
        });
    }
    if (reportDumpingBtn) {
        reportDumpingBtn.addEventListener('click', () => { postNuiMessage('user:reportIllegalDumping'); statusBar.textContent = 'Reporting illegal dumping...'; });
    }
    const forceInternetOutageBtn = document.getElementById('force-internet-outage-btn');
    const internetHubSelect = document.getElementById('internet-hub-select');
    if (forceInternetOutageBtn && internetHubSelect) {
        forceInternetOutageBtn.addEventListener('click', () => {
            const selectedHub = internetHubSelect.value;
            if (selectedHub) { postNuiMessage('admin:forceInternetOutage', { hubId: selectedHub }); statusBar.textContent = `Forcing outage for hub ${selectedHub}...`; }
            else { statusBar.textContent = 'Select internet hub.'; }
        });
    }
    const forceWaterLeakBtn = document.getElementById('force-water-leak-btn');
    if (forceWaterLeakBtn) {
        forceWaterLeakBtn.addEventListener('click', () => { postNuiMessage('admin:forceWaterLeak'); statusBar.textContent = 'Forcing random water leak...'; });
    }
    const spawnTrashBtn = document.getElementById('spawn-trash-btn');
    if (spawnTrashBtn) {
        spawnTrashBtn.addEventListener('click', () => { postNuiMessage('admin:spawnTrash'); statusBar.textContent = 'Spawning admin trash pile...'; });
    }

    const adminRequestInstallBtn = document.getElementById('admin-request-internet-install-btn');
    const adminPropertyIdInput = document.getElementById('admin-property-id-input');
    const adminInternetTierSelect = document.getElementById('admin-internet-tier-select');
    if(adminRequestInstallBtn && adminPropertyIdInput && adminInternetTierSelect) {
        adminRequestInstallBtn.addEventListener('click', () => {
            const propertyId = adminPropertyIdInput.value; const tierId = adminInternetTierSelect.value;
            if(propertyId && tierId) { postNuiMessage('admin:requestInternetInstall', { propertyId, tierId }); statusBar.textContent = `Admin: Requesting install for ${propertyId}, tier ${tierId}`; }
            else { statusBar.textContent = 'Admin: Property ID and Tier required.'; }
        });
    }

    postNuiMessage('NUI_READY');
    statusBar.textContent = 'Dashboard loaded. Waiting for initial data...';

    if (!window.GetParentResourceName) { // Browser Mock
        console.warn("Running in browser mode. NUI messages will be logged.");
        setTimeout(() => {
            checkAdminPermissions(true);
            const mockCfg = {
                Internet: {
                    ServiceTiers: { basic: {label: "Basic", speed: "25 Mbps", price: 50}, premium: {label: "Premium", speed: "200 Mbps", price: 100}},
                    Hubs: { 'LS_Main': {label: 'LS Main'}, 'Paleto': {label: 'Paleto Hub'} }
                },
                Power: { Zones: { 'Downtown': {label: 'Downtown'}, 'Vinewood': {label: 'Vinewood'} } },
                Water: { Sources: { 'Reservoir': {label: 'Reservoir'} } },
                Trash: { PublicBins: [{id:'bin1',label:'Bin 1', coords: {x:0,y:0,z:0}, capacity:100}], LargeDumpsters: [{id:'dump1',label:'Dumpster 1', coords: {x:0,y:0,z:0}, capacity: 500}]}
            };
            window.cachedConfigData = mockCfg;

            const mockInitial = {
                isAdmin: true, config: mockCfg,
                power: {'Downtown': {label:"DT Grid",isBlackout:false}, 'Vinewood':{label:"VW Hills",isBlackout:true}},
                water: {sources:{'Reservoir':{label:"Cool Reservoir",currentLevel:75000,capacity:100000,alertThreshold:0.2}}, leaks:[{id:'leak_1',locationDescription:"near Legion", isLeaking:true}]},
                internet: {
                    hubs: {'LS_Main':{label:"LS Exchange",isDown:false,cc:10,mc:100}, 'Paleto':{label:"Paleto Hub",isDown:true,cc:5,mc:20}},
                    playerProperties: [ {property_id:'prop1', label:'My House', address:'123 Davis Ave'}, {property_id:'prop2', label:'Garage Unit', address:'Unit 5, Industrial Rd'} ],
                    subscriptions: {'prop1': {property_id:'prop1', citizenid:'test', provider:'LS_Main', speed_tier:'premium', is_active:true, last_payment:Date.now()}},
                    pendingInstallations: {}
                },
                trash: {public_bins:{'bin1':{id:'bin1',label:'Legion Bin',load:50,capacity:100, coords:{x:0,y:0,z:0}}}, large_dumpsters:{}, illegal_dumps:[]}
            };
            window.dispatchEvent(new MessageEvent('message', { data: { type: 'UPDATE_DATA', dataType: 'initial_load', payload: mockInitial } }));

            setTimeout(() => {
                 window.dispatchEvent(new MessageEvent('message', {data: {type: 'UPDATE_DATA', dataType: 'internet_pending_install_update', payload: { property_id: 'prop2', citizenid:'test', description: 'Install Basic ADSL', status:'open', ticket_id: 101, speed_tier: 'basic'} }}));
            }, 2000);
        }, 500);
    }
});
