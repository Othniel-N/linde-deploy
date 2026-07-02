/** @type {Handler} */
export const handler = async (input) => {
  const result = {};

  // === Face Recognition Logic ===
  if (input.name) {
    result.name = input.name;
    result.authorized = false;
    result.alert_level = 'warning';
    result.severity = 'medium';
  }

  // === People Detection & Crowd Detection Logic ===
  if (typeof input.people_count !== 'undefined' && input.people_count > 0) {
    result.people_count = input.people_count;

    if (input.people_count >= 1 && input.people_count <= 2) {
      result.P_Count = `${input.people_count} people (Normal Activity)`;
      result.detection_type = 'Normal Activity';
      result.alert_level = 'info';
      result.severity = 'low';
      result.isFlagged = true;  // NEW: Flag for >=1
    } else if (input.people_count >= 3 && input.people_count <= 5) {
      result.P_Count = `${input.people_count} people (Moderate Activity)`;
      result.detection_type = 'Moderate Activity';
      result.alert_level = 'info';
      result.severity = 'low';
      result.isFlagged = true;  // NEW: Flag for >=1
    } else if (input.people_count >= 6 && input.people_count <= 10) {
      result.P_Count = `${input.people_count} people detected (High Activity)`;
      result.detection_type = 'High Activity';
      result.alert_level = 'warning';
      result.severity = 'medium';
      result.isFlagged = true;  // Already flags, but explicit
    } else if (input.people_count > 10) {
      result.P_Count = `${input.people_count} people detected (Crowd Congestion)`;
      result.detection_type = 'Crowd Congestion';
      result.alert_level = 'critical';
      result.severity = 'high';
      result.isFlagged = true;  // Already flags, but explicit
    }
  }

  // === Vehicle Detection Logic ===
  if (typeof input.vehicle_count !== 'undefined' && input.vehicle_count > 0) {
    result.vehicle_count = input.vehicle_count;

    if (input.vehicle_count >= 1 && input.vehicle_count <= 3) {
      result.Vehicle_Count = `${input.vehicle_count} vehicles (Light Traffic)`;
      result.detection_type = 'Light Traffic';
      result.alert_level = 'info';
      result.severity = 'low';
    } else if (input.vehicle_count >= 4 && input.vehicle_count <= 5) {
      result.Vehicle_Count = `${input.vehicle_count} vehicles (Moderate Traffic)`;
      result.detection_type = 'Moderate Traffic';
      result.alert_level = 'info';
      result.severity = 'low';
    } else if (input.vehicle_count >= 6 && input.vehicle_count <= 10) {
      result.Vehicle_Count = `${input.vehicle_count} vehicles detected (Heavy Traffic)`;
      result.detection_type = 'Heavy Traffic';
      result.alert_level = 'warning';
      result.severity = 'medium';
    } else if (input.vehicle_count > 10) {
      result.Vehicle_Count = `${input.vehicle_count} vehicles detected (Congestion)`;
      result.detection_type = 'Vehicle Congestion';
      result.alert_level = 'critical';
      result.severity = 'high';
    }
  }

  // === Safety Violation Logic ===
  if ('helmet' in input && 'vest' in input) {
    if (input.helmet !== 'yes' && input.vest !== 'yes') {
      result.Safety_Violation = 'No Helmet & No Vest';
      result.alert_level = 'critical';
      result.severity = 'high';
      result.violation_count = 2;
    } else if (input.helmet !== 'yes') {
      result.Safety_Violation = 'No Helmet';
      result.alert_level = 'warning';
      result.severity = 'medium';
      result.violation_count = 1;
    } else if (input.vest !== 'yes') {
      result.Safety_Violation = 'No Vest';
      result.alert_level = 'warning';
      result.severity = 'medium';
      result.violation_count = 1;
    } else {
      result.Safety_Violation = 'None';
      result.alert_level = 'info';
      result.severity = 'low';
      result.compliant = true;
      result.violation_count = 0;
    }
  }

  // === Intrusion Detection Logic ===
  if (input.detections && typeof input.detections === 'object' && !Array.isArray(input.detections)) {
    const personDetected = input.detections.person === true;
    const vehicleDetected = input.detections.vehicle === true;

    if (personDetected || vehicleDetected) {
      result.person = personDetected;
      result.vehicle = vehicleDetected;

      if (personDetected && vehicleDetected) {
        result.alert_level = 'critical';
        result.severity = 'high';
      } else if (personDetected) {
        result.alert_level = 'warning';
        result.severity = 'medium';
      } else if (vehicleDetected) {
        result.alert_level = 'info';
        result.severity = 'low';
      }
    }
  }

  // === Demographics Logic (NEW FORMAT) ===
  if (typeof input.male_count !== 'undefined' || typeof input.female_count !== 'undefined' || typeof input.kid_count !== 'undefined') {
    const maleCount = input.male_count || 0;
    const femaleCount = input.female_count || 0;
    const kidCount = input.kid_count || 0;
    const totalCount = maleCount + femaleCount + kidCount;

    if (totalCount > 0) {
      result.male_count = maleCount;
      result.female_count = femaleCount;
      result.kid_count = kidCount;
      result.total_count = totalCount;

      if (kidCount > 0) {
        result.Demographics_Category = 'Child';
        result.Target_Demographics = 'flagged';
        result.alert_level = 'warning';
        result.severity = 'medium';
      } else if (maleCount > femaleCount) {
        result.Demographics_Category = 'Adult Male';
        result.Target_Demographics = 'flagged';
        result.alert_level = 'info';
        result.severity = 'low';
      } else if (femaleCount > maleCount) {
        result.Demographics_Category = 'Adult Female';
        result.Target_Demographics = 'flagged';
        result.alert_level = 'info';
        result.severity = 'low';
      } else if (maleCount === femaleCount && maleCount > 0) {
        result.Demographics_Category = 'Mixed';
        result.Target_Demographics = 'flagged';
        result.alert_level = 'info';
        result.severity = 'low';
      }

      if (totalCount > 10) {
        result.alert_level = 'warning';
        result.high_demographic_count = true;
      }
    }
  }

  // === Demographics Logic (LEGACY FORMAT) ===
  else if ((input.age_group || input.gender) && !('helmet' in input) && !('vest' in input)) {
    const ageGroup = input.age_group || 'Unknown';
    const gender = input.gender || 'Unknown';

    result.Age_Group = ageGroup;
    result.Gender = gender;
    result.Target_Demographics = 'flagged';

    if (ageGroup === 'Minor' || ageGroup === 'kid') {
      result.Demographics_Category = 'Child';
      result.alert_level = 'warning';
      result.severity = 'medium';
    } else if (ageGroup === 'Major' || ageGroup === 'adult') {
      result.Demographics_Category = 'Adult';
      result.alert_level = 'info';
      result.severity = 'low';
    } else {
      result.Demographics_Category = 'General';
      result.alert_level = 'info';
      result.severity = 'low';
    }
  }

  // === Wrong Direction Detection Logic ===
  if (input.detections && typeof input.detections === 'object' && !Array.isArray(input.detections) && input.detections.vehicle === true && input.detections.wrong_direction === true) {
    result.wrong_direction = true;
    result.alert_level = 'critical';
    result.severity = 'high';
  }

  // === Overspeed Detection Logic ===
  if (input.detections && Array.isArray(input.detections) && input.detections.length > 0) {
    const hasSpeedData = input.detections.some(d => typeof d.speed === 'number');
    if (hasSpeedData) {
      const thresholds = { moderate: 40, high: 45, critical: 50 };
      const speeding = input.detections.filter(d => typeof d.speed === 'number' && d.speed > thresholds.moderate);
      if (speeding.length > 0) {
        result.overspeed_detected = true;
        result.speeding_vehicles = speeding.map(v => ({ speed: v.speed, class: v.class || 'Unknown' }));
        result.max_speed = Math.max(...speeding.map(v => v.speed));
        result.speeding_count = speeding.length;
        result.alert_level = result.max_speed > 50 ? 'critical' : 'warning';
        result.severity = result.max_speed > 50 ? 'high' : 'medium';
      } else {
        result.overspeed_detected = false;
        result.alert_level = 'info';
      }
    }
  }

  // === ANPR (License Plate Recognition) Logic ===
  if (input.plate_text) {
    const plateText = (input.plate_text || '').toString().trim().toUpperCase();
    const confidence = parseFloat(input.confidence) || 0;
    const detectionConfidence = parseFloat(input.detection_confidence) || 0;

    result.plate_text = plateText;
    result.confidence = confidence;
    result.detection_confidence = detectionConfidence;

    const blacklistedPlates = ['MH12AB1234', 'DL01XY9999', 'KA05ZZ5555'];
    result.blacklisted = blacklistedPlates.includes(plateText);

    const employee = input.employee || null;
    result.authorized = !!employee;
    result.employee_name = employee?.name || null;
    result.employee_email = employee?.email || null;

    if (result.blacklisted) {
      result.vehicle_category = 'Blacklisted';
      result.alert_level = 'critical';
      result.severity = 'high';
      result.message = `BLACKLISTED: ${plateText}`;
    } else if (result.authorized) {
      result.vehicle_category = 'Authorized Employee';
      result.alert_level = 'info';
      result.severity = 'low';
      result.message = `Welcome ${employee.name} (${employee.email})`;
    } else {
      result.vehicle_category = 'Unauthorized';
      result.alert_level = 'warning';
      result.severity = 'medium';
      result.message = `Unknown Vehicle: ${plateText}`;
    }

    if (confidence < 0.7 || detectionConfidence < 0.7) {
      result.low_confidence = true;
    }

    // FORCE FLAG SO AUTHORIZED EVENTS ARE SAVED
    if (result.authorized) {
      result.isFlagged = true;
    }
  }

  // === Tailgating Logic (ALWAYS FLAG WHEN PRESENT) ===
  // Accepts: input.detections.tailgating (boolean), violators (number), totalPeople (number)
  if (input.detections && typeof input.detections === 'object' && !Array.isArray(input.detections)) {
    const isTailgating = input.detections.tailgating === true;
    const violators = Number(input.detections.violators ?? 0);
    const totalPeople = Number(input.detections.totalPeople ?? 0);

    if (isTailgating || violators > 0) {
      result.tailgating = true;
      result.violators = violators;
      result.total_people = totalPeople;

      // Strong flagging to ensure persistence and broadcast
      result.alert_level = 'critical';
      result.severity = 'high';
      result.message = `Tailgating detected: ${violators} violator(s) among ${totalPeople} people`;
      result.isFlagged = true;
    } else if (typeof input.detections.tailgating !== 'undefined') {
      // Tailgating explicitly reported as false – still set a low-level signal
      result.tailgating = false;
      result.violators = violators;
      result.total_people = totalPeople;
      result.alert_level = result.alert_level || 'info';
      result.severity = result.severity || 'low';
      // Do not force-flag when explicitly false
    }
  }

  // === NEW: Idle Time (Dwell Time) Detection Logic ===
  const IDLE_THRESHOLD_MS = 300000; // Configurable: 5 minutes in milliseconds (edit here in GoRules editor)
  if (typeof input.dwell_time_ms !== 'undefined' && input.dwell_time_ms >= IDLE_THRESHOLD_MS && input.detections?.vehicle_id) {
    result.idle_time_exceeded = true;
    result.dwell_time_ms = input.dwell_time_ms;
    result.dwell_time_formatted = `${Math.floor(input.dwell_time_ms / 60000)}m ${Math.floor((input.dwell_time_ms % 60000) / 1000)}s`;
    result.detection_type = 'Idle Vehicle';
    result.alert_level = 'warning';
    result.severity = 'medium';
    result.vehicle_id = input.detections.vehicle_id;
    result.message = `Vehicle ${result.vehicle_id} has been idle for ${result.dwell_time_formatted}`;
    result.isFlagged = true; // Force flagging for persistence and broadcast
  } else if (input.detections?.vehicle_id) {
    result.idle_time_exceeded = false;
    result.dwell_time_ms = input.dwell_time_ms || 0;
    result.detection_type = 'Vehicle Present';
    result.alert_level = 'info';
    result.severity = 'low';
  }

  if (input.eventType === 'frisking_violation' && input.plate_text) {
    const plateText = (input.plate_text || '').toString().trim().toUpperCase();
    
    result.vehicle_frisking = true;
    result.plate_text = plateText;
    result.confidence = parseFloat(input.confidence) || 0;
    result.detection_confidence = parseFloat(input.detection_confidence) || 0;
    
    // Check authorization via ANPR API (assumes input.authorized is pre-validated)
    result.authorized = input.authorized || false;
    
    // Blacklist check
    const blacklistedPlates = ['MH12AB1234', 'DL01XY9999', 'KA05ZZ5555'];
    result.blacklisted = blacklistedPlates.includes(plateText);
    
    if (result.blacklisted) {
      result.vehicle_category = 'Blacklisted';
      result.alert_level = 'critical';
      result.severity = 'high';
      result.message = `Vehicle frisking violation detected for BLACKLISTED plate ${plateText}`;
    } else if (!result.authorized) {
      result.vehicle_category = 'Unauthorized';
      result.alert_level = 'critical';
      result.severity = 'high';
      result.message = `Vehicle frisking violation detected for plate ${plateText}`;
    } else {
      result.vehicle_category = 'Authorized';
      result.alert_level = 'info';
      result.severity = 'low';
      result.message = `Vehicle frisking: Authorized vehicle ${plateText}`;
    }
    
    // Low confidence warning
    if (result.confidence < 0.7 || result.detection_confidence < 0.7) {
      result.low_confidence = true;
    }
    
    // ALWAYS flag vehicle frisking events for persistence
    result.isFlagged = true;
  }

  return result;
};
