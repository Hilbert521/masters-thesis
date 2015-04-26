clear all;

%% Matice systemu

dt = 0.0114;

A = [1 dt   0  0            0;
     0 1    dt 0            0;
     0 0    0  1            1;
     0 0    0  0.9860       0;
     0 0    0  0            1];
 
B = [0; 0; 0; 1.1720e-04; 0];

%% Kovariancni matice mereni

measurement_covariance = diag([0.0058, 0.08, 0, 0, 0]);

% pocet stavu systemu 
n_states = size(A, 1);

% pocet vstupu do systemu
u_size = size(B, 2);

%% Pomocne promenne

% delka predikcniho horizontu
horizon_len = 200;

%% Matice U

n_variables = 20;

U = zeros(horizon_len, n_variables);

U(1:10, 1:10) = eye(10);
U(11:20, 11) = 1;
U(21:30, 12) = 1;
U(31:40, 13) = 1;
U(41:50, 14) = 1;
U(51:60, 15) = 1;
U(61:70, 16) = 1;
U(71:80, 17) = 1;
U(81:90, 18) = 1;
U(91:100, 19) = 1;
U(101:200, 20) = 1;
 
%% Matice A_roof
% n = delka predikcniho horizontu
% A_roof = [A;
%           A^2;
%           A^3;
%           ...;
%           A^n]; 

A_roof = zeros(horizon_len * n_states, n_states);

for i=1:horizon_len
   A_roof(((i-1)*n_states+1):(n_states*i), :) = A^i; 
end

%% Matice B_roof
% n = delka predikcniho horizontu
% B_roof = [B,        0,        0,   0;
%           AB,       B,        0,   0;
%           A^2B,     AB,       B,   0;
%           ...;
%           A^(n-2)B, A^(n-1)B, ..., 0;
%           A^(n-1)B, A^(n-2)B, ..., B;

B_roof = zeros(horizon_len * n_states, horizon_len);

for i=1:horizon_len
    for j=1:i
        B_roof((i-1)*n_states+1:i*n_states, ((j-1)*u_size+1):j*u_size) = (A^(i - j))*B;
    end
end

B_roof = B_roof*U;

%% Matice Q_roof
% n = pocet stavu
% Q = n*n
%     diagonala, penalizace odchylek stavu
% S = n*n
%     penalizace odchylky posledniho stavu
% Q_roof = [Q,   0,   ...,  0;
%           0,   Q,   ...,  0;
%           ..., ..., Q,    0;
%           0,   ..., ...,  S];

Q = [1.07, 0, 0, 0, 0;
     0, 0, 0, 0, 0;
     0, 0, 0, 0, 0;
     0, 0, 0, 0, 0;
     0, 0, 0, 0, 0];

S = [10, 0, 0, 0, 0;
     0, 0, 0, 0, 0;
     0, 0, 0, 0, 0;
     0, 0, 0, 0, 0;
     0, 0, 0, 0, 0];
 
Q_roof = zeros(n_states * horizon_len, n_states * horizon_len);

for i=1:horizon_len
    Q_roof((i-1)*n_states+1:i*n_states, (i-1)*n_states+1:i*n_states) = Q; 
end

Q_roof(end-n_states+1:end, end-n_states+1:end) = S;

%% Matice P_roof
% penalizace akcnich zasahu
% P_roof = [P,   0,   ...,  0;
%           0,   P,   ...,  0;
%           ..., ..., P,    0;
%           0,   ..., ...,  P];

P = 0.000001;

P_roof = zeros(n_variables, n_variables);

for i=1:n_variables
    P_roof(i, i) = P;
end

for i=11:19
    P_roof(i, i) = 10*P; 
end

P_roof(20, 20) = 100*P;

%% Matice H
% matice kvadratickeho clenu kvadraticke formy QP

H = B_roof'*Q_roof*B_roof + P_roof;
H_inv = (0.5*H)^(-1);

%% ?�dic� smy?ka s MPC

% delka simulace
simu_len = 1000;

time(1) = 0;

% elevator_vel = 0.25*cos(0:0.003:2*pi*20);
% aileron_vel = 0.25*sin(0:0.003:2*pi*20);
% 
% elevator_pos = integrate(elevator_vel, dt);
% aileron_pos = integrate(aileron_vel, dt);
% aileron_pos = aileron_pos - mean(aileron_pos);

% reference position
x_ref = zeros(1, 3000);

reference = zeros(1, horizon_len);

% x_ref((simu_len+horizon_len)/2+1:end) = 1 + 0.2*sin(linspace(1, 20, (simu_len+horizon_len)/2))';
    
% initial conditions
x(:, 1) = [0; 0; 0; 0; 0];

% vektor akcnich zasahu
u = zeros(horizon_len, u_size);

% history of used actions
u_hist(1) = 0;

% saturace akcnich zasahu
saturace = 800;

% max speed
max_speed = 0.35;

u_sat = 0;

% kalman variables

kalmanCovariance = eye(5);
estimate(:, 1) = [0; 0; 0; 0; 0];

xd_pure_integration(1) = x(1, 1);

%% support matrices

% process noise
R_kalman = diag([1, 1, 1, 1, 0.02]);

% measurement noise
Q_kalman = diag([150]);
    
% measurement distribution
C_kalman = [0, 1, 0, 0, 0];

for i=2:simu_len
    
    time(i) = time(i-1)+dt;
    
    % create the sensor measurement     
    measurement(:, i-1) = createMeasurement(x(:, i-1), measurement_covariance);
    
    % pure integration of px4flow velocity     
    xd_pure_integration(i) = xd_pure_integration(i-1) + measurement(2, i-1)*dt;

    [estimate(:, i), kalmanCovariance] = kalman(estimate(:, i-1), kalmanCovariance, measurement(2, i-1), u_sat, A, B, R_kalman, Q_kalman, C_kalman); 
        
% Input governor
    reference = estimate(1, i);
    for j=2:horizon_len
        diference = reference(j-1) - x_ref(j+i-1);
        
        if (diference > max_speed*dt)
            diference = max_speed*dt;
        elseif (diference < -max_speed*dt)
            diference = -max_speed*dt;
        end
        
        reference(j) = reference(j-1) - diference;
    end

%     reference(1:horizon_len) = x_ref(i:i+horizon_len-1);

    my_ref = zeros(n_states*horizon_len, 1);
    my_ref(1:n_states:n_states*horizon_len, 1) = reference;
    
    X_0 = A_roof*(estimate(:, i)) - my_ref;
    c = (X_0'*Q_roof*B_roof)';
    
    u_cf = H_inv*(c./(-2));
        
    % stretch the action vector to the whole horizon     
    u_cf = U*u_cf;
    
    % simulace predikce z aktualniho vektoru akcnich zasahu
    x_cf(:, 1) = estimate(:, i);
    for j=2:horizon_len
        x_cf(:, j) = A*x_cf(:, j-1) + B*u_cf(j-1);
    end

    % take the first action
    u_sat = u_cf(1);
    
    % saturuj akcni zasah     
    if (u_sat > saturace)
        u_sat = saturace;
    elseif (u_sat < -saturace)
        u_sat = -saturace;
    end
    
    u_hist(i) = u_sat;

    % Compute new states     
    x(:, i) = A*x(:, i-1) + (B*u_sat);
        
end

%% plotting for thesis

hFig = figure(10);

subplot(1, 2, 1);

hold off
plot(linspace(0, dt*(i-1), i), x_ref(1:i), 'r', 'LineWidth', 1.5);
hold on
plot(linspace(0, dt*(i-1), i), x(1, 1:i), 'b', 'LineWidth', 1.5);
title('Position');
legend('Setpoint', 'Position', 'Location', 'NorthEast');
xlabel('Time [s]');
ylabel('Position [m]');
axis([0 dt*i -0.1 1.75]);

set(hFig, 'Units', 'centimeters');
set(hFig, 'Position', [0 0 21 21*0.5625/2])

subplot(1, 2, 2);

hold off
plot(time(1:end-1), measurement(2, 1:(i-1)), 'r', 'LineWidth', 1.5);
hold on
plot(time(1:end-1), estimate(2, 1:(i-1)), 'b', 'LineWidth', 1.5);
plot(time(1:end-1), ones(1, length(time(1:end-1)))*0.34, 'k--');
title('Speed');
legend('Simulated measurement', 'Estimated speed', 'Speed limit');
xlabel('Time [s]');
ylabel('Velocity [m/s]');
axis([0 dt*i -0.25 1]);

set(hFig, 'Units', 'centimeters');
set(hFig, 'Position', [0 0 21 21*0.5625/2])

drawnow;

pause(2);

tightfig(hFig);