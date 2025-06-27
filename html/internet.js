document.addEventListener('DOMContentLoaded', () => {
    const dashboard = document.getElementById('internet-dashboard');
    const propertiesList = document.getElementById('properties-list');
    const propertyTemplate = document.getElementById('property-template');
    const loadingIndicator = document.getElementById('loading');
    const closeBtn = document.getElementById('close-btn');
    const body = document.body;

    // Available internet tiers - could also be fetched from Lua if they are dynamic
    const INTERNET_TIERS = [
        { id: 'Basic', name: 'Basic Plan (50 Mbps)' },
        { id: 'Premium', name: 'Premium Plan (200 Mbps)' },
        { id: 'Ultra', name: 'Ultra Plan (1 Gbps)' }
    ];

    // Mock data for development - replace with actual data from Lua
    // { propertyId: 'prop1', address: '123 Main St', currentTier: 'Basic', isRouterInstalled: true, isSubscribed: true }
    let playerData = [];

    function sendNuiMessage(action, data = {}) {
        fetch(`https://${GetParentResourceName()}/${action}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8',
            },
            body: JSON.stringify(data),
        }).catch(err => console.error("NUI Message Error:", action, err));
    }

    function renderProperty(property) {
        const propertyElement = propertyTemplate.content.cloneNode(true).querySelector('.property-item');
        propertyElement.dataset.propertyId = property.propertyId;

        propertyElement.querySelector('.property-address').textContent = property.address || `Property ID: ${property.propertyId}`;

        const statusEl = propertyElement.querySelector('.property-status');
        const tierEl = propertyElement.querySelector('.property-tier');
        const actionsContainer = propertyElement.querySelector('.actions');
        actionsContainer.innerHTML = ''; // Clear previous actions

        if (property.isSubscribed) {
            statusEl.textContent = property.isRouterInstalled ? 'Active' : 'Pending Installation';
            statusEl.className = `property-status font-medium ${property.isRouterInstalled ? 'text-green-400' : 'text-yellow-400'}`;
            tierEl.textContent = INTERNET_TIERS.find(t => t.id === property.currentTier)?.name || property.currentTier;

            if (!property.isRouterInstalled) {
                const installButton = document.createElement('button');
                installButton.textContent = 'Request Technician (Install Router)';
                installButton.className = 'btn btn-secondary mt-2 w-full';
                installButton.onclick = () => {
                    // This button is more of a UX hint; actual install is via /installinternet command by a tech.
                    // We could send a message to Lua to e.g. set a flag or notify a technician service.
                    sendNuiMessage('requestInstall', { propertyId: property.propertyId });
                    alert('A technician will need to visit your property to install the router. Use /installinternet if you are a technician.');
                };
                actionsContainer.appendChild(installButton);
            } else {
                // Upgrade options
                const currentTierIndex = INTERNET_TIERS.findIndex(t => t.id === property.currentTier);
                const availableUpgrades = INTERNET_TIERS.filter((tier, index) => index > currentTierIndex);

                if (availableUpgrades.length > 0) {
                    const upgradeSelect = document.createElement('select');
                    upgradeSelect.className = 'select-input';
                    availableUpgrades.forEach(tier => {
                        const option = document.createElement('option');
                        option.value = tier.id;
                        option.textContent = tier.name;
                        upgradeSelect.appendChild(option);
                    });
                    actionsContainer.appendChild(upgradeSelect);

                    const upgradeButton = document.createElement('button');
                    upgradeButton.textContent = 'Upgrade Plan';
                    upgradeButton.className = 'btn btn-primary mt-2 w-full';
                    upgradeButton.onclick = () => {
                        const selectedTier = upgradeSelect.value;
                        sendNuiMessage('upgradeTier', { propertyId: property.propertyId, newTier: selectedTier });
                    };
                    actionsContainer.appendChild(upgradeButton);
                } else {
                    const p = document.createElement('p');
                    p.textContent = 'You are on the highest available tier.';
                    p.className = 'text-gray-400 mt-2';
                    actionsContainer.appendChild(p);
                }
            }
        } else { // Not subscribed
            statusEl.textContent = 'Not Subscribed';
            statusEl.className = 'property-status font-medium text-red-400';
            tierEl.textContent = 'None';

            const subscribeSelect = document.createElement('select');
            subscribeSelect.className = 'select-input';
            INTERNET_TIERS.forEach(tier => {
                const option = document.createElement('option');
                option.value = tier.id;
                option.textContent = tier.name;
                subscribeSelect.appendChild(option);
            });
            actionsContainer.appendChild(subscribeSelect);

            const subscribeButton = document.createElement('button');
            subscribeButton.textContent = 'Subscribe Now';
            subscribeButton.className = 'btn btn-success mt-2 w-full';
            subscribeButton.onclick = () => {
                const selectedTier = subscribeSelect.value;
                sendNuiMessage('subscribe', { propertyId: property.propertyId, tier: selectedTier });
            };
            actionsContainer.appendChild(subscribeButton);
        }
        return propertyElement;
    }

    function displayProperties(properties) {
        propertiesList.innerHTML = ''; // Clear existing list
        if (properties && properties.length > 0) {
            loadingIndicator.style.display = 'none';
            properties.forEach(property => {
                propertiesList.appendChild(renderProperty(property));
            });
        } else {
            loadingIndicator.textContent = 'You do not own any properties or no internet data found.';
            loadingIndicator.style.display = 'block';
        }
    }

    // Listen for messages from Lua
    window.addEventListener('message', (event) => {
        const { action, data } = event.data;

        if (action === 'openInternetUI') {
            playerData = data.properties || []; // Store player properties and internet status
            displayProperties(playerData);
            body.classList.remove('hidden');
            dashboard.classList.remove('hidden');
        } else if (action === 'updatePropertyData') {
            // Find and update a specific property in playerData
            const index = playerData.findIndex(p => p.propertyId === data.propertyId);
            if (index !== -1) {
                playerData[index] = { ...playerData[index], ...data };
                displayProperties(playerData); // Re-render to reflect changes
            }
        } else if (action === 'closeInternetUI') {
            closeUI();
        }
    });

    function closeUI() {
        body.classList.add('hidden');
        dashboard.classList.add('hidden');
        sendNuiMessage('closeNUI');
    }

    // Close button functionality
    closeBtn.addEventListener('click', closeUI);

    // Handle Escape key to close NUI
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeUI();
        }
    });

    // For development: Simulate receiving data after a delay
    // setTimeout(() => {
    //     const mockProperties = [
    //         { propertyId: 'prop_123_main_st', address: '123 Main St', currentTier: 'Basic', isRouterInstalled: true, isSubscribed: true },
    //         { propertyId: 'prop_456_oak_ave', address: '456 Oak Ave', currentTier: 'None', isRouterInstalled: false, isSubscribed: false },
    //         { propertyId: 'prop_789_pine_ln', address: '789 Pine Ln', currentTier: 'Premium', isRouterInstalled: false, isSubscribed: true },
    //     ];
    //     window.postMessage({ action: 'openInternetUI', data: { properties: mockProperties } }, '*');
    // }, 500);
});
